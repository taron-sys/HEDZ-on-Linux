# Technical notes

Everything learned while making H.E.D.Z. (1998) run under Wine. Reference environment: Fedora 44, `wine-core 11.0-3.fc44`
(staging, wow64, 32-bit DLLs in `/usr/lib/wine-wow64/wine/i386-windows`), Mesa/RADV, KDE Plasma 6 (Wayland, 4K at 185 %).
Addresses are virtual addresses; DLL image base `0x10000000`, `Hedz.exe` image base `0x400000`.

## 1. Game-side obstacles (no code patch needed)

- **"H.E.D.Z will only run if your backdrop is set to High Colour (16bit)"** — `sub_46f980` compares `[0x599004] == 16`,
  set by `sub_490d60` from the *Win9x* registry key `HKLM\Config\0001\Display\Settings\BitsPerPixel` (REG_SZ, `atoi`).
  Wine ignores that key, so setting it to `"16"` satisfies the strict `==` while the real display stays 32-bit.
- **CD check** (`sub_46e030`; the result shows up as "Error - N"): the exe's drive must be `GetDriveType()==DRIVE_CDROM`
  (error 3 otherwise) and creating `D:\Hedz\test` for writing must *fail* (error 1 otherwise). It also checks the sizes of
  `Music\*.MUS`. Hence `D:` is registered as `cdrom` (`HKLM\Software\Wine\Drives`, `dosdevices/d:`) and a read-only empty
  file `Hedz/test` exists. The `Hedz` directory itself must stay writable: the game writes `GameSave\`, `HedzScore.dat`
  and `LastLoadedHeds.txt` there (a read-only directory = the "deny" sound when saving).
- Game settings: `HKLM\Software\Vis Interactive\Hedz` in the **32-bit** view (`ClipPlane, Models, Lighting, ResMode,
  MusicLevel, SoundLevel, Difficulty, FullScreen, …`).

## 2. Patch table (Wine DLLs)

All are binary patches against the stock DLLs:

- `ddraw.dll` sha256 `ea490bbead63d2929b36e55044e29a06031618d7322978a04e958b5b91c96e71`
- `wined3d.dll` sha256 `0397d27ec116533e1cb7d1f7aa388c6f054e34db375b127c8c2310de00ef0d53`

`build_patches.py` checks the original bytes before every write. Code caves live in the zero padding at the end of `.text`
(VA 0x1003d170–0x1003e000), sources in `asm/`, position independent (`call 1f; pop`) because the DLL may be relocated.
A patched copy must have the string `Wine builtin DLL` changed (done by the script) or Wine silently loads its own copy.
The prefix has `ddraw`/`wined3d` overrides `native,builtin`, and the launcher copies the patched files into `syswow64`.

| # | Symptom | Cause | Patch |
|---|---|---|---|
| 1 | Crash on *New Game*: `Assertion failed: iface->lpVtbl == &d3d_viewport_vtbl, viewport.c:1212` | the game Releases its viewport to 0, then calls `DeleteViewport` on it | `unsafe_impl_from_IDirect3DViewport3` (0x1003afd7) returns NULL instead of asserting |
| 2 | ~1M× `Box (0,0,0)-(8192,0,0) is invalid` | `SetExecuteData` maps the vertex buffer with a zero-filled box (bottom/back = 0) | box init at 0x100154b1 rewritten to `{0,0,0,1,0,1}` |
| 3 | same warning for index buffers etc. | ddraw maps zero-height boxes all over; this wined3d rejects them | **wined3d**: NOP the `top<bottom` (0x101e9c64) and `front<back` (0x101e9c7e) checks |
| 4 | stale / garbled geometry | Wine copies execute-buffer vertices only in `SetExecuteData`; the game rewrites them in place and only calls `Execute` | cave 0x1003d400: `d3d_device1_Execute` calls `SetExecuteData(buf,&buf->data)` first (`asm/reup.s`) |
| 5 | `Operation requires 0x2 access, but texture only has 0xd` on texture uploads | video-memory textures were GPU-only; wined3d's CPU blit fallback cannot write them | cave 0x1003d200 in `ddraw_texture_init`: drop RENDER_TARGET from plain textures' main texture and add CPU access (`asm/cpuacc.s`). Doing it for RT/DS surfaces crashes |
| 6 | software-drawn surfaces stay empty | the game Locks a system-memory surface once, keeps the pointer and writes later; Wine keeps serving its cached GPU copy | `asm/dirty.s` `dirty7`: empty Lock/Unlock of system-memory surfaces before `TEXTUREHANDLE` binding (hook 0x1000d0c5) and before v1 `Blt`/`BltFast` (vtable slots 0x1003e494/0x1003e49c) |
| 7 | **3D world missing (black)** | `D3DOP_MATRIXLOAD` ignored; `D3DOP_MATRIXMULTIPLY` updates the handle storage but never the wined3d WORLD/VIEW/PROJ transform | cave 0x1003d700 (`asm/mat.s`): MATRIXLOAD → `IDirect3DDevice::SetMatrix(dev+0xc, hDest, src)` (jump table 0x100465c0, opcode 4); MATRIXMULTIPLY hook at 0x10015ba7 calls `SetMatrix(hDest, dest)` after the multiply. **Decisive for the world** |
| 8 | **hed and held items missing** | see below | the `Blt` hook also does `DDBLT_COLORFILL` **and `DDBLT_DEPTHFILL`** on system-memory 16 bpp surfaces on the CPU (`cpufill` in `asm/dirty.s`) |

### Why the hed and the held items were missing (patch 8)

They are drawn by the game's own *software voxel renderer* into small system-memory surfaces (64×64 sprite textures, 256×256
in the front end), copied into textures and drawn as large alpha-keyed billboard quads. That renderer owns a software
z-buffer: a system-memory `DDSCAPS_ZBUFFER` surface. Its clear routine (`sub_4ac330`) first calls
`Blt(DDBLT_DEPTHFILL|WAIT, 0xffff)` and only clears the memory itself *if that call fails*. Wine returns success but clears
a GPU-side buffer, so the memory the renderer z-tests against stayed 0 and every voxel was rejected → empty texture →
transparent quad. How it was found: a debug build recorded, per texture handle bound by `SetRenderState(TEXTUREHANDLE)`,
how non-empty the surface memory was; hed handles were all zero while world textures were full, so the *source* was empty.
`dev/dbgbuild.py` builds a DLL with a cave's asm swapped for a debug variant.

### Experimental patches (off by default, `BP_ENABLE=swap,gsd,usrmem`)

Tried while hunting the above and found *not* needed: `swap` (SwapTextureHandles remaps only the table), `gsd`
(`GetSurfaceDesc` returns `lpSurface` for system-memory textures like the original DirectDraw), `usrmem` (caller-owned memory
for plain 16 bpp video textures so a Lock pointer stays valid).

### ddraw internals (this build)

- `d3d_execute_buffer_execute` = `sub_10015880(buffer, device)` (cdecl); opcode jump table at 0x100465b0. Locals:
  `[ebp-0xc4]` instruction data, `[ebp-0xc0]` element size, `edi` count.
- `ddraw_get_object(table, handle-1, type)` = 0x10025e40 (cdecl); types: 2 matrix, 4 surface.
- `SetExecuteData` = 0x100154a0 (stdcall 8). Buffer struct: `+0x20` lpData, `+0x24` D3DEXECUTEDATA, `+0x60` src vertex pos.
- device struct: `+0` Device7, `+4` v3, `+8` v2, `+0xc` v1 (v1 vtable `SetMatrix` at +0x40). Surface struct: `+0` Surface7,
  `+0x10` v1 interface, `+0x18` Texture2; v1 surface vtable at 0x1003e480.
- device3 `SetRenderState` = 0x1000d050 (vtable slot 0x10045c38).

## 3. Patches to Hedz.exe (`patch_exe.py`)

1. **Music** (0x48bbe8, `0x10 → 0x40`): the game opens `Music\N.MUS` with `mmioOpenA(…, MMIO_EXCLUSIVE)`, keeps that handle,
   and its own wrapper opens the same file again with sharing. Wine enforces share modes (the original CD file system did
   not), so the second open failed (`status c0000043`) and the music never started. → `MMIO_DENYNONE`.
2. **Medic at 0 HP** (`.rsrc` VirtualSize/SizeOfImage +0x40000): fault `read access to 0x60DB04 at 0x48401B`. The loop at
   0x48401b does `fld [eax+idx*4]` with `idx` a u16 from a 16-entry frame record and `eax=[0x4d77ec]` a float table loaded
   from an RCDATA resource at the end of the image. An out-of-range index (only seen at HP 0) reads past the image end
   (0x608000). Windows had mapped memory there; Wine does not. Zero-filled slack makes the stray vertex read 0.0.
   *Verified in game:* the medic can now drain his own HP to 0 without a crash. (The root cause, why the frame index is out
   of range at HP 0, is still unknown; at worst one stray vertex of the dying medic model reads as 0.0.)

## 4. Running under gamescope

- **No Wine virtual desktop under gamescope**: the X screen already is 640×480; a virtual desktop only shows an empty teal
  desktop and hides the dialog. **Without** gamescope the virtual desktop *is* needed (`explorer /desktop=HEDZ,640x480`):
  otherwise the primary surface is monitor-sized and wined3d logs `Depth stencil is smaller than the primary color buffer` /
  `Silently ignoring depth and target clear with mismatching sizes`.
- **Do not run `wine …` (even `wine reg`) on the prefix on your desktop before starting gamescope.** That starts a
  wineserver + explorer on the *desktop's* X display (here 2076×1168 at 185 % scale). It lingers a few seconds; the game then
  attaches to that desktop instead of gamescope's X server: its virtual screen is offset (x = 4152), the clip window belongs
  to the other X connection, every request on it fails with `BadWindow` (`X_UnmapWindow`, `X_MapWindow`, `X_GrabPointer`)
  and the window sits off-screen → black. Wine's X11 driver passes such errors to Xlib's default handler, which `exit(1)`s —
  that was the original "crash on New Game". The launcher kills any wineserver first; the old `wine reg` calls are gone.
- `tools/xerrbt.c` (LD_PRELOAD, injected with `env` because gamescope strips `LD_PRELOAD`) overrides `_XDefaultError` to
  ignore `BadWindow`, and prints a backtrace for other X errors (found the cause: `NtUserMoveWindow → win32u → winex11 → XFlush`).
- **Leftover processes**: Wine's `winedevice.exe`/`services.exe` survive `wineserver -k` and ignore SIGTERM; gamescope's
  `gamescopereaper` waits for all descendants, so gamescope never exits. `tools/hedz-wrap.sh` runs wine, then
  `wineserver -k` and `kill -9` of that prefix's leftover service processes (matched through `/proc/<pid>/environ`).
- `ENABLE_GAMESCOPE_WSI=0` keeps gamescope's Vulkan WSI layer out of the game (the game renders through Wine's OpenGL, via
  zink on some stacks); it was an early suspect for the crash and is harmless to leave off.

## 5. Dead ends

- **dgVoodoo2** (2.55, 2.63, 2.87.x): crashes inside its `DDraw.dll` during the primary-surface `CreateSurface`.
- **wined3d Vulkan renderer**: cannot create a 16-bit (B5G6R5) swapchain.
- `VideoMemorySize`, forcing ZENABLE off/CULLMODE none/fog: no effect on the missing world.
- Making video textures CPU-only with a separate draw texture turned every texture white; GPU access on system-memory
  surfaces moved fills to the GPU and later Locks downloaded over the game's CPU drawing.
- **Filling the screen without gamescope**: creating the swapchain *windowed* (patch `0x10026d6b: not eax; and eax,1 →
  mov eax,1` in `ddraw_set_cooperative_level`) so wined3d stretches the 640×480 picture to a monitor-sized window did **not**
  work.
- Wine does not fake the 16 bpp mode itself; there is no `winecfg` setting for the strict depth check.

## 6. Game internals

- Front-end state `[0x4cb05c]`: 2 = hed-case screen (draw `sub_42f760`), 3/9 = hed spin display (`sub_4328a0`: software voxel
  renderer into a 256×256 system-memory surface, then a colour-keyed Blt). Frame loop `sub_4811e0`; front-end draw `sub_43d7f0`.
- Texture streaming: system-memory staging surfaces → `BltFast` into video textures, plus a `SwapTextureHandles` trick around
  `GetRenderState(TEXTUREHANDLE)`.
- The game uses neither `GetExecuteData` nor `TransformVertices`.
- Music: `Music\N.MUS` via Miles Sound System (`MSS32.DLL`, `AIL_open_stream`).
- Built-in screenshot routine `0x489ae0` writes `c:\Screenshots\HedzScrnShot<N>.bmp` (trigger key unknown).

## 7. Testing / debugging methods

- **End-to-end on a real GPU without touching the desktop**: `dev/gsplay.sh` runs the real launcher in *headless* gamescope
  (`--backend headless`, its own Xwayland on `:1`) and drives the game with xdotool: the game reads the mouse through
  **DirectInput**, so use *relative* moves plus mousedown/up, not absolute moves or `xdotool click`. It grabs gamescope's
  PipeWire stream (`gst-launch-1.0 pipewiresrc path=<node> ! videoconvert ! pngenc`) because x11grab of Xwayland is black.
  Always use a separate test prefix (`HEDZ_PREFIX`), never one you are playing in.
- Xvfb + llvmpipe + `wine explorer /desktop=…` works for quick checks but differs slightly from a real GPU.
- Useful `WINEDEBUG` channels: `+ddraw` (execute ops, surfaces, Blt), `warn+d3d`, `+d3d` (vertex/matrix dumps), `+file`,
  `+loaddll`, `+x11drv,+win,+event` (window handling). Logs get huge; filter them.
- Memory inspection: attach `winedbg` **once** per run (`printf 'x /12x 0xADDR\ndetach\nquit\n' | wine winedbg <pid>`);
  a second attach fails with error 5. "Can't attach: error 5" usually means the game already crashed.
- Static analysis: any disassembler on `Hedz.exe`; for the DLLs `objdump -d -M intel` is enough. Wine 11.0 sources
  (`dlls/ddraw/executebuffer.c`, `device.c`, `surface.c`) at `raw.githubusercontent.com/wine-mirror/wine/wine-11.0/…`.

## 8. Open items

- Minor graphical glitches; warnings `wined3d_texture_load_location requires 0x2 access` (colour-keyed Blts into render-target
  surfaces) and `surface_cpu_blt Filter LINEAR not supported`.
- Why the medic's frame index is out of range at 0 HP (the crash itself is fixed, see §3).
- No scaling or mouse confinement without gamescope.
- Upstreaming patches 1–7 to Wine, or rebuilding ddraw from source (toolchain: clang + lld-link, or mingw).
