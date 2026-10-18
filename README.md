# hedz-linux — run *H.E.D.Z.* (1998) on Linux with Wine

Scripts and Wine source patches that make **H.E.D.Z. – Head Extreme Destruction Zone** (Vis Interactive / Hasbro, 1998, a
DirectDraw / Direct3D 3 game) playable on a modern Linux desktop under Wine, in its own prefix:

- the 3D world, the hed carousel, the heds on the player and the items in their hands render correctly,
- music, sound effects, saving and high scores work,
- fullscreen scaling and mouse confinement through [gamescope](https://github.com/ValveSoftware/gamescope).

**You need your own copy of the game** (the original CD / an image of it). Nothing of the game, and no Microsoft or Wine
binaries, are included in this repository. The patched `ddraw.dll` is built *on your machine* from the source of the
Wine you have installed.

> **Status / compatibility.** Developed and tested on **Fedora 44, wine-core 11.0 (staging, wow64), Mesa/RADV (AMD),
> KDE Plasma 6 on Wayland**. The Wine fixes are source patches for `dlls/ddraw` (`patches/`, written against `wine-11.0`);
> `build-ddraw.sh` downloads the source matching your installed Wine, applies them and builds only `ddraw.dll`. Other 11.x
> versions may work if the patches still apply — see [Other Wine builds](#other-wine-builds).

## Install

Requirements: `wine` (+ `wineserver`) 11.0, `python3`, `curl`, `podman` or `docker` (builds `ddraw.dll`; no toolchain on
the host needed), `7z` (p7zip/7zip).
Optional: `gamescope` (recommended), `gcc` + libX11 headers (builds a small safety shim used under gamescope).

```sh
git clone <this repo> hedz-linux && cd hedz-linux
./install.sh /path/to/hedz.cue        # also accepts .img/.iso or a folder with the disc contents
./run-hedz.sh
```

`install.sh` (about a minute plus the Wine source download, nothing is installed system-wide):

1. extracts the disc to `~/.wine-hedz-cd` (`HEDZ_CD`),
2. patches `Hedz.exe` (music; crash when the field medic's HP reaches 0; keeps `Hedz.exe.orig`),
3. makes that folder look like a CD (see [How it works](#how-it-works)); only `Hedz/` stays writable for saves,
4. creates a fresh Wine prefix `~/.wine-hedz` (`HEDZ_PREFIX`) and sets the required registry values,
5. builds the patched `ddraw.dll` into `~/.wine-hedz/patches` (`build-ddraw.sh`; downloads the Wine source once, builds in a
   container),
6. builds `tools/xerrbt.so` (optional).

Uninstall: `chmod -R u+w ~/.wine-hedz-cd && rm -rf ~/.wine-hedz ~/.wine-hedz-cd`.

## Run

```sh
./run-hedz.sh                  # fullscreen gamescope, 640x480 upscaled, mouse confined (default)
HEDZ_WINDOWED=1 ./run-hedz.sh  # gamescope in a window
HEDZ_NOGS=1 ./run-hedz.sh      # no gamescope: 640x480 Wine desktop window (mouse can leave it)
```

Game flow: launcher dialog → *New Game* → *START* → pick a world → *PLAY* → pick heds → *PLAY*.
(The launcher dialog is the game's own; click *New Game* there.)

| Variable | Effect |
|---|---|
| `HEDZ_NOGS=1` | no gamescope |
| `HEDZ_NOVD=1` | with `HEDZ_NOGS`: no virtual desktop. The window becomes monitor-sized and the 640x480 picture sits in its corner; the z-buffer may be disabled. Only for debugging |
| `HEDZ_WINDOWED=1` | gamescope in a window |
| `HEDZ_GSARGS="…"` | extra gamescope arguments |
| `HEDZ_GSWSI=1` | keep gamescope's Vulkan WSI layer loaded into the game (off by default) |
| `HEDZ_LOG=1\|2\|3` | write `hedz.log` next to the script: 1 errors + ddraw, 2 + process/exceptions, 3 + window/X11 tracing (huge) |
| `HEDZ_BT=1` | also preload the X-error shim without gamescope |
| `HEDZ_PREFIX`, `HEDZ_CD` | prefix / disc locations (used by every script) |

Saves and high scores are written to `~/.wine-hedz-cd/Hedz/` (`GameSave/`, `HedzScore.dat`, `LastLoadedHeds.txt`).
Game settings live in the prefix registry (`HKLM\Software\Vis Interactive\Hedz`, 32-bit view).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Not installed: run ./install.sh …` | prefix, patched DLLs or disc copy not where `HEDZ_PREFIX`/`HEDZ_CD` point |
| "…will only run if your backdrop is set to High Colour (16bit)" | the display registry key is missing: re-run `install.sh` (sets `HKLM\Config\0001\Display\Settings\BitsPerPixel=16`) |
| Error 1/3 dialog ("Error - N") at start | the CD check failed: `D:` must be type *cdrom* and `D:\Hedz\test` must be a read-only file. `install.sh` sets both |
| Black or all-white 3D / missing textures | `ddraw.dll` in the prefix is not the patched one; just start via `run-hedz.sh` (it copies it in) |
| No music | `Hedz.exe` is not patched (re-run `python3 patch_exe.py`) |
| Black gamescope window, `BadWindow … X_UnmapWindow` | a stray wineserver on another display; the launcher kills it at start. Don't run `wine …` on the same prefix on your desktop *before* the launcher |
| `gamescopereaper` stays after quitting | handled by `tools/hedz-wrap.sh`; if you start gamescope yourself, use the wrapper |
| Anything else | `HEDZ_LOG=2 ./run-hedz.sh`, reproduce, and open an issue with `hedz.log` |

Known limitations: without gamescope the game cannot be scaled to the screen (Wine does not stretch fullscreen DirectDraw
here) and the mouse can leave the window; some minor graphical glitches remain (warnings about colour-keyed blits into
render targets).

## How it works

Short version (details and addresses in [docs/TECHNICAL.md](docs/TECHNICAL.md)):

- **16-bit check:** the game compares the *Windows 9x* registry value `Config\0001\Display\Settings\BitsPerPixel` with 16.
  Setting that value satisfies the strict `== 16` check even though the real display is 32-bit.
- **CD check:** requires a CD-ROM drive type and that creating `D:\Hedz\test` fails → `D:` is typed `cdrom` and a
  read-only `test` file exists.
- **Wine's ddraw execute-buffer path** (D3D3) is barely used by other games and has several bugs that HEDZ hits. They are
  fixed by the source patches in `patches/` (built into your own `ddraw.dll`; stock `wined3d` is used):
  viewport assert, zero-sized buffer maps, vertex re-upload, CPU access for textures, dirty-marking of system-memory
  surfaces and depend on this), and `D3DOP_MATRIXLOAD`/`MATRIXMULTIPLY` (the 3D world).
- **Hedz.exe** gets two patches (`patch_exe.py`): music sharing mode, and zero-filled slack behind the image.
- **gamescope:** no Wine virtual desktop under it; `tools/xerrbt.so` ignores a fatal X `BadWindow` error;
  `tools/hedz-wrap.sh` removes Wine's leftover service processes so gamescope can exit.

## Other Wine builds

`./build-ddraw.sh` reads `wine --version`, downloads that version's source from dl.winehq.org, applies `patches/*.patch`
and builds `ddraw.dll`. `run-hedz.sh` refuses to start when the installed Wine no longer matches the version the DLL was built
for (ddraw talks to wined3d through an internal interface), so re-run `./build-ddraw.sh` after a Wine update. If a patch no
longer applies the script says which one; the patches are small and touch `dlls/ddraw/{viewport,executebuffer,device,surface}.c`.
`HEDZ_BUILD=host` uses a host `i686-w64-mingw32-gcc` instead of a container; `HEDZ_WINE_VERSION=…` forces a version. Tested
only with wine-11.0. The long-term fix is to upstream the patches to Wine; contributions welcome.

## Repository layout

| Path | Purpose |
|---|---|
| `install.sh` | one-time setup |
| `run-hedz.sh` | launcher |
| `extract_disc.py` | disc image → files (handles raw 2352-byte sectors) |
| `patch_exe.py` | `Hedz.exe` patches |
| `build-ddraw.sh`, `patches/` | builds the patched `ddraw.dll` from Wine's source (`patches/*.patch`) |
| `legacy/` | the earlier address-based binary patches (`build_patches.py`, `asm/`), only valid for Fedora's wine-core 11.0-3 |
| `tools/` | `hedz-wrap.sh`, `xerrbt.c` (LD_PRELOAD shim), `Containerfile` (ddraw build toolchain) |
| `dev/` | developer helpers: `gsplay.sh` (automated end-to-end test) |
| `docs/TECHNICAL.md` | findings, patch table, internals, debugging methods |

## License

MIT for everything in this repository (see `LICENSE`) except `patches/`, which are modifications of Wine and therefore
LGPL-2.1-or-later like Wine itself. H.E.D.Z. is © its respective owners. No Wine binaries are redistributed: `ddraw.dll`
is built on your machine.
