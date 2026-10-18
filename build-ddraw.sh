#!/bin/bash
# Builds a patched ddraw.dll for HEDZ from the source of the Wine version you have installed.
#   ./build-ddraw.sh                 -> $HEDZ_PREFIX/patches/ddraw.dll  (default prefix ~/.wine-hedz)
# Fetches the matching Wine source tarball, applies patches/*.patch, builds only ddraw.dll (i686) and installs it.
# The toolchain runs in a podman/docker container (tools/Containerfile); with HEDZ_BUILD=host the host's
# i686-w64-mingw32-gcc is used instead. Only ddraw.dll is produced: wined3d and everything else stay stock.
#   HEDZ_WINE_VERSION=11.0   override the version (default: from `wine --version`)
#   HEDZ_BUILD=container|host
#   HEDZ_CACHE=<dir>         downloads and build trees (default ~/.cache/hedz-wine)
set -e
HERE="$(dirname "$(readlink -f "$0")")"
PREFIX="${HEDZ_PREFIX:-$HOME/.wine-hedz}"
CACHE="${HEDZ_CACHE:-$HOME/.cache/hedz-wine}"
die() { echo "error: $*" >&2; exit 1; }

VER="${HEDZ_WINE_VERSION:-$(wine --version 2>/dev/null | sed -n 's/^wine-\([0-9.]*[0-9]\).*/\1/p')}"
[ -n "$VER" ] || die "cannot determine the Wine version (is wine installed?)"
case "$VER" in
  11.0|11.0.*) ;;
  *) echo "warning: the patches were written and tested against wine-11.0; building for $VER may fail to apply or misbehave." >&2 ;;
esac
# stable releases live in <major>.0/, development releases in <major>.x/
case "$VER" in *.0|*.0.*) DIR="${VER%%.*}.0" ;; *) DIR="${VER%%.*}.x" ;; esac

mkdir -p "$CACHE"
TAR="$CACHE/wine-$VER.tar.xz"
if [ ! -f "$TAR" ]; then
  echo "== downloading wine-$VER"
  curl -fL -o "$TAR.part" "https://dl.winehq.org/wine/source/$DIR/wine-$VER.tar.xz" || die "download failed"
  mv "$TAR.part" "$TAR"
fi

echo "== extracting and patching"
SRC="$CACHE/src-$VER"
rm -rf "$SRC"; mkdir -p "$SRC"
tar -xf "$TAR" -C "$SRC" --strip-components=1
for p in "$HERE"/patches/*.patch; do
  ( cd "$SRC" && patch -p1 --silent < "$p" ) || die "$(basename "$p") does not apply to wine-$VER"
done

BLD="$CACHE/build-$VER"
mkdir -p "$BLD"
# $1 = source dir, run inside the build dir
BUILD_SH='
set -e
[ -f Makefile ] || "$1/configure" --enable-archs=i386 --disable-tests --without-x --without-freetype \
    --without-alsa --without-pulse --without-oss --without-gstreamer --without-cups --without-sdl --without-usb \
    --without-v4l2 --without-pcap --without-krb5 --without-gnutls --without-sane --without-vulkan >/dev/null
make -j"$(nproc)" dlls/ddraw/all
i686-w64-mingw32-strip -o ddraw.stripped.dll dlls/ddraw/i386-windows/ddraw.dll'
echo "== building ddraw.dll"
if [ "${HEDZ_BUILD:-container}" = host ]; then
  ( cd "$BLD" && bash -c "$BUILD_SH" _ "$SRC" )
else
  RT=$(command -v podman || command -v docker) || die "need podman or docker (or HEDZ_BUILD=host with mingw-w64)"
  "$RT" image inspect hedz-wine-build >/dev/null 2>&1 \
    || "$RT" build -t hedz-wine-build -f "$HERE/tools/Containerfile" "$HERE/tools"
  "$RT" run --rm -v "$CACHE:/cache:Z" -w "/cache/build-$VER" hedz-wine-build \
    bash -c "$BUILD_SH" _ "/cache/src-$VER"
fi

# A copy of a builtin DLL that still carries the "Wine builtin DLL" marker is ignored by Wine (it loads its own),
# so change the marker; the prefix has ddraw set to native,builtin.
mkdir -p "$PREFIX/patches"
python3 - "$BLD/ddraw.stripped.dll" "$PREFIX/patches/ddraw.dll" "$VER" <<'PY'
import sys
d = bytearray(open(sys.argv[1], 'rb').read())
i = d.find(b"Wine builtin DLL"); assert i > 0, "builtin marker not found"
d[i:i+16] = b"Wine nativ  DLL\0"
open(sys.argv[2], 'wb').write(d)
open(sys.argv[2] + ".version", 'w').write(sys.argv[3] + "\n")
PY
echo "wrote $PREFIX/patches/ddraw.dll (built from wine-$VER)"
