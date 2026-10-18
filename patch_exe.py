#!/usr/bin/env python3
"""Patch Hedz.exe in the extracted disc copy. Idempotent; keeps Hedz.exe.orig next to it.
Usage: python3 patch_exe.py [path-to-Hedz.exe]     (default: $HEDZ_CD/Hedz/Hedz.exe, i.e. ~/.wine-hedz-cd/Hedz/Hedz.exe)

Patches (VA; image base 0x400000, .text file offset 0x400 = VA 0x401000):
 1. 0x48bbe8: mmioOpenA(..., MMIO_EXCLUSIVE 0x10) -> MMIO_DENYNONE 0x40. The game keeps an exclusive winmm handle on
    Music\\N.MUS open and then opens the same file again with sharing; Wine enforces the share mode (the original CD
    file system did not), so the second open failed and the music never started.
 2. .rsrc VirtualSize and SizeOfImage +0x40000. When the field medic hed reaches 0 HP the vertex code at 0x48401b reads
    float_table[u16 index] with an index outside the table, which lives in an RCDATA resource at the very end of the
    image (fault at 0x60DB04, image end 0x608000). Windows had mapped memory behind the image, Wine does not. The extra
    pages are zero-filled, so the stray vertex reads as 0.0 instead of crashing. (Verified in game: the medic can
    drain his own HP to 0 without a crash.)
"""
import hashlib, os, shutil, stat, struct, sys

ORIG_SHA256 = "1a3034530112d5af9475416d698c52c45ebfa008a4ea3f681fb300932b8fcf7c"      # retail Hedz.exe, before patching

default = os.path.join(os.environ.get("HEDZ_CD", os.path.expanduser("~/.wine-hedz-cd")), "Hedz", "Hedz.exe")
path = sys.argv[1] if len(sys.argv) > 1 else default


def off(va):
    return va - 0x401000 + 0x400


# the pristine exe is Hedz.exe.orig once we have patched; before that it is Hedz.exe itself
orig = path + ".orig" if os.path.exists(path + ".orig") else path
got = hashlib.sha256(open(orig, "rb").read()).hexdigest()
if got != ORIG_SHA256:
    sys.exit(f"{orig} is not the retail Hedz.exe these patches were written for (sha256 {got}, expected {ORIG_SHA256})")

d = bytearray(open(path, "rb").read())
pe = struct.unpack_from("<I", d, 0x3c)[0]
opt = pe + 24
sh = opt + struct.unpack_from("<H", d, pe + 20)[0] + 3 * 40            # .rsrc is the 4th (last) section
assert d[sh:sh + 5] == b".rsrc", "unexpected Hedz.exe (section layout differs)"
assert len(d) == 935936, "unexpected Hedz.exe size - these patches are for the retail 1998 build"

todo = []
if d[off(0x48bbe7):off(0x48bbe7) + 2] == bytes([0x6a, 0x10]):
    d[off(0x48bbe8)] = 0x40
    todo.append("music")
else:
    assert d[off(0x48bbe7):off(0x48bbe7) + 2] == bytes([0x6a, 0x40]), "unexpected bytes at 0x48bbe7"
vsize = struct.unpack_from("<I", d, sh + 8)[0]
if vsize < 0x40000:
    struct.pack_into("<I", d, sh + 8, vsize + 0x40000)
    struct.pack_into("<I", d, opt + 56, struct.unpack_from("<I", d, opt + 56)[0] + 0x40000)
    todo.append("medic")

if not todo:
    print("already patched:", path)
    sys.exit(0)

dirn = os.path.dirname(path)
dmode = os.stat(dirn).st_mode
os.chmod(dirn, dmode | stat.S_IWUSR)
if os.path.exists(path):
    os.chmod(path, os.stat(path).st_mode | stat.S_IWUSR)
if not os.path.exists(path + ".orig"):
    shutil.copy(path, path + ".orig")
open(path, "wb").write(d)
os.chmod(path, os.stat(path).st_mode & ~(stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))
os.chmod(dirn, dmode)
print("patched", path, "(" + ", ".join(todo) + ")")
