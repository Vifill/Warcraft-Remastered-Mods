#!/bin/sh
# Started by the Wine wrapper's StartupScript. While Wine runs, keeps the mod files
# (VERSION.dll, w1r_mods.ini, and WineMetalGL's opengl32.dll + winemetalgl.dll) in the
# game's x86 folder, so they are there the first time the game is installed by Battle.net
# and come back after Battle.net updates. Files are replaced by rename, never in place,
# so a running game keeps the copy it loaded.
D="$HOME/Library/Application Support/Warcraft1Mac"
SRC="$D/mods"
GAME="$D/Wrapper.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Warcraft I Remastered/x86"
LOCK="$D/.sync.pid"
LOG="$D/sync.log"

if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then exit 0; fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

idle=0
while :; do
  if [ -d "$GAME" ]; then
    for f in VERSION.dll w1r_mods.ini opengl32.dll winemetalgl.dll; do
      [ -f "$SRC/$f" ] || continue
      if ! cmp -s "$SRC/$f" "$GAME/$f"; then
        cp "$SRC/$f" "$GAME/.$f.tmp" && mv -f "$GAME/.$f.tmp" "$GAME/$f" \
          && echo "$(date '+%F %T') updated $f" >> "$LOG"
      fi
    done
  fi
  if pgrep -f "Warcraft1Mac/Wrapper.app.*wineserver" >/dev/null 2>&1; then idle=0; else idle=$((idle + 5)); fi
  [ "$idle" -ge 60 ] && exit 0
  sleep 5
done
