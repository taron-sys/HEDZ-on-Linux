#!/usr/bin/env python3
"""Build the patched ddraw.dll / wined3d.dll for HEDZ from your installed stock Wine DLLs.

Usage:  python3 build_patches.py [outdir]      (default outdir: $HEDZ_PREFIX/patches, i.e. ~/.wine-hedz/patches)
Needs:  GNU as/ld/objcopy (binutils) for the .s files in ./asm.
Env:    HEDZ_WINE_DLLS=<dir>  directory with the 32-bit stock ddraw.dll/wined3d.dll (default: auto-detected)
Only Fedora's wine-core 11.0 (staging, wow64) DLLs are known; any other build fails the sha256 check below on purpose.

Every patch checks the original bytes first, so this fails loudly if the stock DLLs change
(e.g. after a Wine update). Addresses are virtual addresses with image base 0x10000000;
for these DLLs file offset == VA - 0x10000000 for .text/.rdata/.data.
See NOTES.md for what each patch does and why.
"""
import hashlib, os, struct, subprocess, sys, tempfile
# Speculative patches that turned out NOT to be needed: off unless enabled via BP_ENABLE=swap,gsd,usrmem.
# They are kept for reference (see docs/TECHNICAL.md).
ENABLE = set(filter(None, os.environ.get('BP_ENABLE', '').split(',')))
SKIP = {'swap', 'gsd', 'usrmem'} - ENABLE

HERE = os.path.dirname(os.path.abspath(__file__))
CANDIDATES = ["/usr/lib/wine-wow64/wine/i386-windows", "/usr/lib64/wine-wow64/wine/i386-windows",
              "/usr/lib/wine/i386-windows", "/usr/lib64/wine/i386-windows", "/usr/lib/i386-linux-gnu/wine/i386-windows"]
STOCK = os.environ.get("HEDZ_WINE_DLLS") or next((d for d in CANDIDATES if os.path.exists(d + "/ddraw.dll")), None)
if not STOCK:
    sys.exit("cannot find Wine's 32-bit ddraw.dll; set HEDZ_WINE_DLLS=<dir containing i386-windows DLLs>")
DDRAW_SHA = "ea490bbead63d2929b36e55044e29a06031618d7322978a04e958b5b91c96e71"
WINED3D_SHA = "0397d27ec116533e1cb7d1f7aa388c6f054e34db375b127c8c2310de00ef0d53"
BASE = 0x10000000


def check_sha(d, want, name):
    got = hashlib.sha256(d).hexdigest()
    if got != want:
        sys.exit(f"{name} in {STOCK} is not the build these patches were written for.\n  expected sha256 {want}\n  found    sha256 {got}\n"
                 "The patches are address-based; a different Wine build needs them re-derived (see docs/TECHNICAL.md).")


def off(va):
    return va - BASE


def asm(name, org, syms):
    """Assemble asm/<name>.s at address org, return raw bytes."""
    with tempfile.TemporaryDirectory() as t:
        o, e, b = (os.path.join(t, x) for x in ("o.o", "o.elf", "o.bin"))
        subprocess.run(["as", "--32", os.path.join(HERE, "asm", name + ".s"), "-o", o], check=True)
        cmd = ["ld", "-m", "elf_i386", f"-Ttext={org:#x}", "-o", e, o]
        for k, v in syms.items():
            cmd[1:1] = ["--defsym", f"{k}={v:#x}"]
        subprocess.run(cmd, check=True)
        subprocess.run(["objcopy", "-O", "binary", "-j", ".text", e, b], check=True)
        nm = subprocess.run(["nm", e], check=True, capture_output=True, text=True).stdout
        labels = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
        return open(b, "rb").read(), labels


def put(d, va, expect, new):
    o = off(va)
    if expect is not None:
        assert d[o:o + len(expect)] == expect, f"{va:#x}: expected {expect.hex()} got {d[o:o+len(expect)].hex()}"
    d[o:o + len(new)] = new


def cave(d, va, code):
    put(d, va, b"\0" * len(code), code)


def jmp(src, dst):
    return b"\xe9" + struct.pack("<i", dst - (src + 5))


def ptr(d, va, old, new):
    put(d, va, struct.pack("<I", old), struct.pack("<I", new))


def strip_builtin_marker(d):
    # Wine ignores a copied DLL that still carries the builtin marker and loads its own instead.
    i = d.find(b"Wine builtin DLL")
    assert i > 0
    d[i:i + 16] = b"Wine nativ  DLL\0"


def build_ddraw():
    d = bytearray(open(f"{STOCK}/ddraw.dll", "rb").read())
    check_sha(d, DDRAW_SHA, "ddraw.dll")

    # 1. unsafe_impl_from_IDirect3DViewport3: return NULL instead of assert() on a foreign/stale pointer
    #    (game releases its viewport, then DeleteViewport()s it -> viewport.c:1212 assert crash on "New Game").
    put(d, 0x1003afd7, bytes.fromhex("c7442408"), bytes.fromhex("31c0c9c3"))

    # 2. d3d_execute_buffer_SetExecuteData: map box was zero-filled (bottom=back=0) -> wined3d rejected the
    #    vertex upload ("Box (0,0,0)-(8192,0,0) is invalid"). Re-init box as {0,0,0,1,0,1}.
    put(d, 0x100154b1, bytes.fromhex("c74405c400000000c74405c80000000083c00883f81872e8"),
        bytes.fromhex("8945c48945c88945cc8945d4408945d08945d8") + b"\x90" * 5)

    # 3. ddraw_texture_init: give plain textures CPU access (cave 0x1003d200, hook at 0x10036da3).
    c, _ = asm("cpuacc", 0x1003d200, {"back": 0x10036da9})
    cave(d, 0x1003d200, c)
    put(d, 0x10036da3, bytes.fromhex("8b8564ffffff"), jmp(0x10036da3, 0x1003d200) + b"\x90")

    # 4. d3d_device1_Execute: call SetExecuteData(buffer, &buffer->data) before every execute, because the
    #    game rewrites vertices in place without calling SetExecuteData again (Wine only copied them there).
    c, _ = asm("reup", 0x1003d400, {"setexec": 0x100154a0, "execute": 0x10015880})
    cave(d, 0x1003d400, c)
    put(d, 0x100089c7, b"\xe8" + struct.pack("<i", 0x10015880 - 0x100089cc),
        b"\xe8" + struct.pack("<i", 0x1003d400 - 0x100089cc))

    # 5. Mark system-memory surfaces dirty (empty Lock/Unlock) before they are used, because the game keeps
    #    raw pointers from one Lock and writes into them later; Wine kept serving the stale GPU copy.
    #    Hooks: SetRenderState(TEXTUREHANDLE) at 0x1000d0c5, IDirectDrawSurface(v1)::Blt/BltFast vtable slots.
    #    The Blt hook also performs COLORFILL into system-memory surfaces on the CPU (see asm/dirty.s cpufill).
    c, lab = asm("dirty", 0x1003d800, {"tex_back": 0x1000d0ca, "orig_blt": 0x10027ab0, "orig_bltfast": 0x10028b70})
    cave(d, 0x1003d800, c)
    put(d, 0x1000d0c5, bytes.fromhex("8b1683c018"), jmp(0x1000d0c5, lab["hook_texhandle"]))
    ptr(d, 0x1003e494, 0x10027ab0, lab["hook_blt"])
    ptr(d, 0x1003e49c, 0x10028b70, lab["hook_bltfast"])

    # 6. D3DOP_MATRIXLOAD (Wine: ignored) and D3DOP_MATRIXMULTIPLY (Wine: result never reached the GPU
    #    transform state). Both now go through IDirect3DDevice::SetMatrix, which copies and propagates to
    #    WORLD/VIEW/PROJECTION. THIS is what made the 3D world render.
    c, lab = asm("mat", 0x1003d700, {"get_obj": 0x10025e40, "mload_cont": 0x10015a15, "mmul_back": 0x10015bad})
    cave(d, 0x1003d700, c)
    ptr(d, 0x100465c0, 0x10015ca0, 0x1003d700)          # execute jump table, opcode 4
    put(d, 0x10015ba7, bytes.fromhex("039d34ffffff"), jmp(0x10015ba7, lab["mmul_hook"]) + b"\x90")

    # 10. Plain 16 bpp video-memory textures get caller-owned memory (DDSD_LPSURFACE) so their Lock() address stays
    #     valid: the game writes hed / equipment sprites through its one-time Lock pointer. See asm/usrmem.s.
    if "usrmem" not in SKIP:
        c, lab = asm("usrmem", 0x1003de90, {"calloc_iat": 0x1006a48c, "back": 0x10036c25})
        cave(d, 0x1003de90, c)
        put(d, 0x10036c1e, bytes.fromhex("0fb64d0c8b7d10"), jmp(0x10036c1e, 0x1003de90) + b"\x90\x90")

    # 9. IDirectDrawSurface::GetSurfaceDesc (v1 vtable slot 0x1003e4d8): return lpSurface for system-memory
    #    textures like the original DirectDraw did (see asm/gsd.s). The game draws its sprites into that pointer.
    if "gsd" not in SKIP:
        orig = struct.unpack_from("<I", d, off(0x1003e4d8))[0]
        c, lab = asm("gsd", 0x1003de00, {"orig_gsd1": orig})
        cave(d, 0x1003de00, c)
        ptr(d, 0x1003e4d8, orig, 0x1003de00)

    # 7. d3d_device2_SwapTextureHandles: only remap the global handle-table entries, do NOT also swap the
    #    surfaces' own Handle fields. The game streams sprites (heds, held items) by calling
    #    Swap(A,B) then Swap(B,A): with Wine's field swap the second call undoes the first and the sprite
    #    keeps the old (empty) texture; with table-only remapping both calls leave handle(A) -> B.
    if "swap" not in SKIP:
        put(d, 0x1000ac42, bytes.fromhex("899620010000"), b"\x90" * 6)   # surf2->Handle = h1 + 1
        put(d, 0x1000ac48, bytes.fromhex("898320010000"), b"\x90" * 6)   # surf1->Handle = h2 + 1


    strip_builtin_marker(d)
    return d


def build_wined3d():
    d = bytearray(open(f"{STOCK}/wined3d.dll", "rb").read())
    check_sha(d, WINED3D_SHA, "wined3d.dll")
    # wined3d_resource_check_box_dimensions: drop the top<bottom and front<back checks. ddraw maps buffers
    # (index buffers, etc.) with zero-height boxes, which this wined3d rejects -> geometry never uploaded.
    put(d, 0x101e9c64, bytes.fromhex("0f83"), b"\x90" * 6)
    put(d, 0x101e9c7e, bytes.fromhex("73"), b"\x90" * 2)
    strip_builtin_marker(d)
    return d


def build_ddraw_min():
    d = bytearray(open(f"{STOCK}/ddraw.dll", "rb").read())
    put(d, 0x1003afd7, bytes.fromhex("c7442408"), bytes.fromhex("31c0c9c3"))
    strip_builtin_marker(d)
    return d


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.environ.get("HEDZ_PREFIX", os.path.expanduser("~/.wine-hedz")), "patches")
    os.makedirs(out, exist_ok=True)
    for name, fn in [("ddraw.full.dll", build_ddraw), ("ddraw.min.dll", build_ddraw_min),
                     ("wined3d.patched.dll", build_wined3d)]:
        open(os.path.join(out, name), "wb").write(fn())
        print("wrote", os.path.join(out, name))
    import shutil
    shutil.copy(f"{STOCK}/wined3d.dll", os.path.join(out, "wined3d.stock.dll"))
    print("wrote", os.path.join(out, "wined3d.stock.dll"))
