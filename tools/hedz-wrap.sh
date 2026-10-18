#!/bin/bash
# Runs the game, then stops EVERYTHING of this wine prefix. Used as gamescope's child: gamescope's reaper waits for all
# descendants, and Wine's winedevice.exe/services.exe survive `wineserver -k` (and ignore SIGTERM), so without this
# gamescope + gamescopereaper + run-hedz.sh never exit after the game is closed.
wine "$@"
wineserver -k 2>/dev/null
sleep 1
for p in $(pgrep -u "$USER" -x 'winedevice.exe|services.exe|plugplay.exe|explorer.exe|svchost.exe|rpcss.exe|conhost.exe|wineboot.exe'); do
  if tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -qx "WINEPREFIX=$WINEPREFIX"; then kill -9 $p 2>/dev/null; fi
done
