#!/bin/sh
# Started by the Wine wrapper's StartupScript. While Wine runs, keeps these files in each
# game's x86 folder, so they are there the first time Battle.net installs a game and come
# back after Battle.net updates:
#   Warcraft I:  VERSION.dll + w1r_mods.ini (mods) and WineMetalGL's opengl32.dll + winemetalgl.dll
#   Warcraft II: VERSION.dll + w2r_mods.ini (mods) and WineMetalGL's opengl32.dll + winemetalgl.dll
# Files are replaced by rename, never in place, so a running game keeps the copy it loaded.
D="$HOME/Library/Application Support/Warcraft1Mac"
SRC="$D/mods"
PF="$D/Wrapper.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)"
LOCK="$D/.sync.pid"
LOG="$D/sync.log"

if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then exit 0; fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# sync_game <x86 folder> <files...>: copy changed files from $SRC by rename
sync_game() {
  dir="$1"; shift
  [ -d "$dir" ] || return 0
  for f in "$@"; do
    [ -f "$SRC/$f" ] || continue
    if ! cmp -s "$SRC/$f" "$dir/$f"; then
      cp "$SRC/$f" "$dir/.$f.tmp" && mv -f "$dir/.$f.tmp" "$dir/$f" \
        && echo "$(date '+%F %T') updated $f in $(basename "$(dirname "$dir")")" >> "$LOG"
    fi
  done
}

idle=0
while :; do
  sync_game "$PF/Warcraft I Remastered/x86" VERSION.dll w1r_mods.ini opengl32.dll winemetalgl.dll
  sync_game "$PF/Warcraft II Remastered/x86" VERSION.dll w2r_mods.ini opengl32.dll winemetalgl.dll
  if pgrep -f "Warcraft1Mac/Wrapper.app.*wineserver" >/dev/null 2>&1; then idle=0; else idle=$((idle + 5)); fi
  [ "$idle" -ge 60 ] && exit 0
  sleep 5
done
