#!/bin/bash
# Automated end-to-end test of run-hedz.sh on a real GPU, without touching your screen or mouse:
# runs the real launcher under HEADLESS gamescope, clicks through launcher -> START -> PLAY -> PLAY into the first level
# (xdotool, relative mouse moves: the game reads the mouse via DirectInput) and saves frames from gamescope's PipeWire
# stream to $OUT/<label>-<step>.png.  Needs: gamescope, xdotool, gst-launch-1.0 with pipewiresrc.
# The X display and PipeWire node are read from this run's own gamescope output, so input never goes to another
# gamescope/X session that happens to be running.
# Usage: dev/gsplay.sh <label>      Env: HEDZ_PREFIX HEDZ_CD (use a test prefix!)  GSP_FRAMES=3  OUT=/tmp/hedz-test
L=${1:-test}; OUT=${OUT:-/tmp/hedz-test}; mkdir -p "$OUT"; HERE="$(dirname "$(readlink -f "$0")")/.."
# with HEDZ_LOG the launcher sends all output to hedz.log instead
LF="$OUT/$L.log"; [ -n "$HEDZ_LOG" ] && { LF="$HERE/hedz.log"; : > "$LF"; }
env -u DISPLAY -u WAYLAND_DISPLAY HEDZ_GSARGS="--backend headless -W 640 -H 480" "$HERE/run-hedz.sh" > "$OUT/$L.log" 2>&1 &
for i in $(seq 1 60); do grep -aq "node ID: [0-9]*" "$LF" && break; sleep 1; done
NODE=$(grep -a -o "node ID: [0-9]*" "$LF" | head -1 | awk '{print $3}')
DNUM=$(grep -a -o "Starting Xwayland on :[0-9]*" "$LF" | head -1 | grep -o ":[0-9]*")
[ -n "$NODE" ] && [ -n "$DNUM" ] || { echo "headless gamescope did not start (see $LF)" >&2; exit 1; }
export DISPLAY=$DNUM
sleep 15
W=$(xdotool search --name "H.E.D.Z." | head -1); [ -n "$W" ] || echo "warning: no game window on $DNUM" >&2
xdotool windowfocus "$W"; xdotool key Return; sleep 8
mv(){ for n in 1 2 3 4 5; do xdotool mousemove_relative -- $(($1/5)) $(($2/5)); sleep 0.1; done; sleep 1; }
clk(){ xdotool mousedown 1; sleep 0.3; xdotool mouseup 1; sleep 6; }
shot(){ timeout 20 gst-launch-1.0 -q pipewiresrc path=$NODE num-buffers=3 ! videoconvert ! pngenc snapshot=true ! filesink location="$OUT/$L-$1.png" >/dev/null 2>&1; }
shot launcher
mv -400 -400; mv 320 150; clk; sleep 4; shot menu1; mv 235 -53; clk; sleep 6; shot menu2; clk; sleep 25
for i in $(seq 1 ${GSP_FRAMES:-3}); do shot play$i; sleep 6; done
WINEPREFIX="${HEDZ_PREFIX:-$HOME/.wine-hedz}" wineserver -k 2>/dev/null
ls "$OUT"/$L-*.png
