# TODO

## Done: Wine fixes as source patches instead of binary patches
The address-based binary patches (pinned to Fedora's wine-core 11.0 sha256) are replaced by seven source patches for
Wine's `ddraw` in `patches/`. `build-ddraw.sh` downloads the Wine source matching `wine --version`, applies them and
builds only `ddraw.dll` in a container; wined3d is stock. The old patches live on in `legacy/`. See `docs/TECHNICAL.md` §2.
Verified on Fedora 44 / wine-core 11.0 (staging, wow64) with `dev/gsplay.sh` in a separate prefix: world, hed, held items
and menus render like the binary build, and the old `Box ... is invalid` / `requires 0x2 access` warnings are gone.

## Still to do

### Verify
- [ ] Play through (not just the first-level screenshot): hed carousel, hed and held items in different levels, music,
      save and high scores, the medic at 0 HP.
- [ ] Test on stock Wine 11.x from Debian/Ubuntu and Arch (or a container), incl. a non-wow64 build. `build-ddraw.sh`
      only configures `--enable-archs=i386`; check that it loads next to a distro's wined3d.
- [ ] Optionally build against the current Wine development release to catch drift early.
- [ ] `build-ddraw.sh` on a machine without podman/docker: document the host toolchain route (`HEDZ_BUILD=host`) as tested.
- [ ] A `BltFast` CPU copy (sysmem 16 bpp -> video texture) existed in the binary build and was not ported because the C
      build did not need it. If sprites ever come out empty on another GPU/driver, that is the first thing to re-add.
- [ ] At exit wined3d logs `Leftover resource ... WINED3D_RTYPE_BUFFER` (execute buffers the game never releases); check
      that the binary build did the same and that it is harmless.

### Tidy
- [ ] `patches/` are plain diffs with a short header; turn them into real `git format-patch` commits when upstreaming.
- [ ] Decide whether to delete `legacy/` once the C patches have been used for a while.

### Upstream
- [ ] Clean up the patches for Wine style, add a ddraw test where one is possible, and send them via a merge request at
      gitlab.winehq.org. Strongest candidates: 0001 (viewport), 0002 (box init), 0003 (execute vertices), 0006 (matrices).
- [ ] Once merged and released, drop the corresponding local patches and set a minimum Wine version.

## Open (unchanged)
- Minor graphical glitches (colour-keyed blits into render targets, `Filter LINEAR not supported`).
- Medic at 0 HP: root cause of the out-of-range frame index.
- No scaling or mouse confinement without gamescope.
