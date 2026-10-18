# TODO: make the Wine fixes shippable (C patches instead of binary patches)

Goal: replace the address-based binary patches in `build_patches.py` / `asm/` (pinned to Fedora's wine-core 11.0 sha256)
with source-level patches against Wine's `ddraw`, so they work on any distro and can be upstreamed.
Background: the binary patches only apply to one exact build; see `docs/TECHNICAL.md` §2 for what each one does and why.

## 1. Set up
- [ ] Get the Wine source at tag `wine-11.0` (`git clone https://gitlab.winehq.org/wine/wine.git`, check out `wine-11.0`,
      or the mirror at github.com/wine-mirror/wine).
- [ ] Check whether Fedora's wine-staging adds changes in `dlls/ddraw` or `dlls/wined3d` that matter. Keep the patches
      against vanilla Wine where possible.
- [ ] Make a working build of just `ddraw.dll` (i686, mingw-w64) that loads in a throwaway prefix as a `native,builtin`
      override. Test with an unmodified build first to confirm the toolchain and loading work.
- [ ] Remember the "Wine builtin DLL" marker: a self-built DLL made with winegcc/mingw may or may not carry it. Make sure Wine
      actually loads the override.

## 2. Port the patches (TECHNICAL.md patch table)
Work in `dlls/ddraw/` unless noted. One commit/patch per item so they can be sent upstream separately.

- [ ] **#1 Viewport assert** (`viewport.c`, `unsafe_impl_from_IDirect3DViewport3`): the game releases its viewport to 0,
      then calls `DeleteViewport` on it. Return NULL (and handle it in callers) instead of asserting.
- [ ] **#2 Zero-filled map box** (`executebuffer.c`, `d3d_execute_buffer_SetExecuteData`): init the box properly instead of
      zero bottom/back.
- [ ] **#3 wined3d box checks**: this is the only wined3d patch. Avoid it by fixing ddraw so it never maps zero-height /
      zero-depth boxes (or passes a NULL box). Goal: ship ddraw only, never a patched wined3d.
- [ ] **#4 Re-upload execute-buffer vertices** (`d3d_device1_Execute`): call `SetExecuteData`-style vertex copy before
      every Execute, because the game rewrites vertices in place.
- [ ] **#5 CPU access for plain video-memory textures** (`ddraw_texture_init` in `surface.c`): drop RENDER_TARGET from
      plain textures' main texture and add CPU access. Do NOT do it for RT/DS surfaces (crashes).
- [ ] **#6 Dirty system-memory surfaces** (empty Lock/Unlock) before `SetRenderState(TEXTUREHANDLE)` binding and before v1
      `Blt`/`BltFast`. See `asm/dirty.s` (`dirty7`).
- [ ] **#7 `D3DOP_MATRIXLOAD` / `D3DOP_MATRIXMULTIPLY`** (`executebuffer.c`): MATRIXLOAD is ignored and MATRIXMULTIPLY never
      reaches the wined3d WORLD/VIEW/PROJ transform. Route both through `IDirect3DDevice::SetMatrix`. This one makes the 3D
      world render.
- [ ] **#8 CPU `DDBLT_COLORFILL` and `DDBLT_DEPTHFILL`** on system-memory 16 bpp surfaces (`asm/dirty.s`, `cpufill`). The
      game's software voxel renderer relies on the depth fill. Find a proper fix in `surface.c` (the fill should hit the
      surface memory, not just a GPU copy) instead of porting the hack as is.
- [ ] Skip `swap`, `gsd`, `usrmem`: they were tried and found not needed.

## 3. Verify
- [ ] Run end to end with `dev/gsplay.sh` in a separate test prefix. Check: world renders, hed carousel, hed and held items,
      music, save and high scores.
- [ ] Check `HEDZ_LOG=1` for the old warnings (`Box ... is invalid`, `requires 0x2 access`).
- [ ] Test on stock Wine 11.x from at least Fedora, Debian/Ubuntu and Arch (or a container). Include a non-wow64 build.
- [ ] Optionally test against the current Wine development release to catch drift early.

## 4. Distribution
- [ ] Commit the result as `patches/*.patch` (against `wine-11.0`) in this repo.
- [ ] `install.sh` / a new `build-ddraw.sh`: fetch the matching Wine source tarball, apply the patches, build only
      `ddraw.dll` (mingw, preferably inside a podman/docker container so users need no toolchain), install it into the prefix.
- [ ] Replace the sha256 guard with a Wine version check: refuse to run on untested versions with a clear message.
- [ ] Stop patching and copying Wine's own `wined3d.dll` (stock one is used). Remove `build_patches.py`, `asm/` and
      `dev/dbgbuild.py`, or move them to `legacy/` for reference.
- [ ] Do not redistribute modified Wine binaries (LGPL). Ship source patches only.
- [ ] `patch_exe.py`: check the sha256 of `Hedz.exe` before patching. Never ship game files.
- [ ] Update README (compatibility section, "Other Wine builds") and `docs/TECHNICAL.md` once done.

## 5. Upstream
- [ ] Clean up the patches for Wine style, then send them via a merge request at gitlab.winehq.org. Patches #1, #2, #4, #7
      are the strongest candidates. Reference a test case or the game as the reproducer.
- [ ] Once merged and released, drop the corresponding local patches and set a minimum Wine version.

## Open (unchanged)
- Minor graphical glitches (colour-keyed blits into render targets, `Filter LINEAR not supported`).
- Medic at 0 HP: root cause of the out-of-range frame index.
- No scaling or mouse confinement without gamescope.
