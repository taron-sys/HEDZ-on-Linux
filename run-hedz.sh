#!/bin/bash
# Launches H.E.D.Z. from the extracted-disc copy ($HEDZ_CD) in its own Wine prefix ($HEDZ_PREFIX).
# Default: fullscreen gamescope (640x480 upscaled, mouse confined). Run ./install.sh once first.
#
#   HEDZ_NOGS=1          no gamescope: a 640x480 Wine virtual-desktop window (the mouse can leave it)
#   HEDZ_NOVD=1          (with HEDZ_NOGS) no virtual desktop; the picture is drawn 1:1 in a corner of a monitor-sized window
#   HEDZ_WINDOWED=1      gamescope in a window instead of fullscreen
#   HEDZ_GSARGS="..."    extra gamescope arguments
#   HEDZ_GSWSI=1         keep gamescope's Vulkan WSI layer loaded into the game (disabled by default)
#   HEDZ_DDRAW=min|full  ddraw patch set: full = all fixes (default), min = only the viewport-assert fix
#   HEDZ_WINED3D=stock   use the unpatched wined3d (default: patched)
#   HEDZ_LOG=1|2|3       write a Wine log to hedz.log next to this script: 1 = errors/ddraw, 2 = + process/exceptions,
#                        3 = + window/X11 tracing (big)
#   HEDZ_BT=1            also preload the X-error shim without gamescope (it is always used under gamescope)
#   HEDZ_PREFIX / HEDZ_CD   locations (defaults ~/.wine-hedz and ~/.wine-hedz-cd)
HERE="$(dirname "$(readlink -f "$0")")"                      # before any cd: $0 may be relative
export WINEPREFIX="${HEDZ_PREFIX:-$HOME/.wine-hedz}"
CD="${HEDZ_CD:-$HOME/.wine-hedz-cd}"
export WINEDEBUG=-all
[ -f "$CD/Hedz/Hedz.exe" ] && [ -f "$WINEPREFIX/patches/ddraw.full.dll" ] || { echo "Not installed: run ./install.sh <disc image> first." >&2; exit 1; }

# A wineserver left over from an earlier run keeps that run's display and X connection; the game would then attach to a
# desktop that does not exist on gamescope's X server (black window, BadWindow errors). Start from a clean session.
wineserver -k 2>/dev/null; sleep 1

if [ -n "$HEDZ_LOG" ]; then
  export WINEDEBUG=err+all,warn+ddraw,fixme+ddraw
  [ "$HEDZ_LOG" = 2 ] && export WINEDEBUG=err+all,warn+ddraw,fixme+ddraw,+process,+seh
  [ "$HEDZ_LOG" = 3 ] && export WINEDEBUG=err+all,+win,+x11drv,+event,+display,+winediag,+ddraw
  exec > >(grep -a --line-buffered -v "radv\|hid:\|wineusb\|ATTENTION" > "$HERE/hedz.log") 2>&1
fi

# Patched DLLs (built by install.sh into $WINEPREFIX/patches) are copied over the prefix's own ddraw/wined3d.
cp "$WINEPREFIX/patches/ddraw.${HEDZ_DDRAW:-full}.dll" "$WINEPREFIX/drive_c/windows/syswow64/ddraw.dll"
cp "$WINEPREFIX/patches/wined3d.${HEDZ_WINED3D:-patched}.dll" "$WINEPREFIX/drive_c/windows/syswow64/wined3d.dll"

# X-error shim (tools/xerrbt.so): ignores the fatal BadWindow error Wine can get from gamescope's Xwayland. gamescope strips
# LD_PRELOAD from its child, so it is injected with `env` right before wine.
BTENV=; SHIM="$HERE/tools/xerrbt.so"
[ -f "$SHIM" ] && BTENV="env LD_PRELOAD=$SHIM"
[ -n "$HEDZ_BT" ] && [ -f "$SHIM" ] && export LD_PRELOAD="$SHIM"

cd "$CD/Hedz" || exit 1
# Without gamescope the screen is monitor-sized, so use a 640x480 Wine virtual desktop: otherwise wined3d disables the
# z-buffer and ignores clears (primary surface monitor-sized vs 640x480 buffers). Under gamescope the X screen already is
# 640x480, and a virtual desktop there only shows an empty teal desktop.
if [ -n "$HEDZ_NOGS" ]; then
  if [ -n "$HEDZ_NOVD" ]; then exec wine 'D:\Hedz\Hedz.exe'; fi
  exec wine explorer /desktop=HEDZ,640x480 'D:\Hedz\Hedz.exe'
fi

[ -z "$HEDZ_GSWSI" ] && export ENABLE_GAMESCOPE_WSI=0
mode=-f; [ -n "$HEDZ_WINDOWED" ] && mode=
# hedz-wrap.sh stops the leftover Wine services after the game exits (else gamescope/gamescopereaper never exit).
gamescope -w 640 -h 480 $mode --force-grab-cursor -S fit $HEDZ_GSARGS -- $BTENV "$HERE/tools/hedz-wrap.sh" 'D:\Hedz\Hedz.exe'
rc=$?
wineserver -k 2>/dev/null
exit $rc
