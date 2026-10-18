#!/bin/bash
# One-time setup. Usage: ./install.sh <hedz.cue | hedz.img | hedz.iso | folder-with-the-disc-contents>
#   HEDZ_PREFIX  Wine prefix to create      (default ~/.wine-hedz)
#   HEDZ_CD      where the disc is extracted (default ~/.wine-hedz-cd)
# You need your own copy of the game; nothing of it is included here.
set -e
HERE="$(dirname "$(readlink -f "$0")")"
PREFIX="${HEDZ_PREFIX:-$HOME/.wine-hedz}"
CD="${HEDZ_CD:-$HOME/.wine-hedz-cd}"
SRC="$1"
die() { echo "error: $*" >&2; exit 1; }
[ -n "$SRC" ] && [ -e "$SRC" ] || die "usage: $0 <hedz.cue|hedz.img|hedz.iso|extracted-disc-folder>"
for c in wine wineserver python3; do command -v $c >/dev/null || die "missing tool: $c"; done
[ -d "$PREFIX" ] && echo "note: $PREFIX already exists, reusing it"

echo "== 1/6  extracting the disc to $CD"
if [ -d "$SRC" ]; then
  mkdir -p "$CD"; chmod -R u+w "$CD" 2>/dev/null || true; cp -a "$SRC"/. "$CD"/
else
  [ -d "$CD" ] && chmod -R u+w "$CD" 2>/dev/null || true
  python3 "$HERE/extract_disc.py" "$SRC" "$CD"
fi
[ -f "$CD/Hedz/Hedz.exe" ] || die "$CD/Hedz/Hedz.exe not found"

echo "== 2/6  patching Hedz.exe (music + medic crash)"
python3 "$HERE/patch_exe.py" "$CD/Hedz/Hedz.exe"

echo "== 3/6  making the copy look like a CD"
# The game insists on running from a CD-ROM drive and on being unable to create D:\Hedz\test (a read-only file with that
# name does that). Everything stays read-only except the Hedz folder, where the game writes saves and high scores.
touch "$CD/Hedz/test"
chmod -R a-w "$CD"
chmod u+w "$CD/Hedz"

echo "== 4/6  creating the Wine prefix $PREFIX"
export WINEPREFIX="$PREFIX" WINEDEBUG=-all
wineboot -u >/dev/null 2>&1 || true
ln -sfn "$CD" "$PREFIX/dosdevices/d:"
wine reg add 'HKLM\Software\Wine\Drives' /v 'd:' /t REG_SZ /d cdrom /f >/dev/null
wine reg add 'HKCU\Software\Wine\DllOverrides' /v ddraw /t REG_SZ /d native,builtin /f >/dev/null
# The game refuses to start unless the (Windows 9x style) display key says 16 bit colour. Wine never reads it itself.
wine reg add 'HKLM\Config\0001\Display\Settings' /v BitsPerPixel /t REG_SZ /d 16 /f >/dev/null
wine reg add 'HKLM\Config\0001\Display\Settings' /v Resolution /t REG_SZ /d 1920,1080 /f >/dev/null
wineserver -k 2>/dev/null || true; sleep 1

echo "== 5/6  building the patched ddraw.dll from the source of your Wine (needs podman or docker)"
HEDZ_PREFIX="$PREFIX" "$HERE/build-ddraw.sh"

echo "== 6/6  building the X-error shim (optional)"
if command -v gcc >/dev/null && gcc -shared -fPIC -O1 -o "$HERE/tools/xerrbt.so" "$HERE/tools/xerrbt.c" -ldl 2>/dev/null; then
  echo "built tools/xerrbt.so"
else
  echo "skipped (needs gcc and libX11 headers). Only matters under gamescope on some setups."
fi
command -v gamescope >/dev/null || echo "note: gamescope is not installed; use HEDZ_NOGS=1 ./run-hedz.sh (small window)"
echo; echo "Done. Start the game with:  $HERE/run-hedz.sh"
