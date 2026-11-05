#!/bin/bash
# dockmag: real macOS 26 Dock magnification reference, Reduce Transparency/Motion/Contrast off, light mode,
# flat grey wallpaper (and the bands wallpaper for the glass look while magnified).
# For each setting (system default size, then largesize 80) the pointer steps across the Dock every 4 pt; each
# step saves a still of the Dock band and the Dock's AX tree (every item's frame). A ScreenCaptureKit video
# records entering, gliding and leaving for the timing. Results: branch dockmag-results (res/dockmag.zip).
set +e
S="$RUNNER_TEMP/dm"; mkdir -p "$S/sweep" "$S/vid"; LOG="$S/log.txt"
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
ts() { python3 -c 'import time; print("%.3f" % time.time())'; }
( T 300 swiftc -O -swift-version 5 drag/rec.swift -o "$RUNNER_TEMP/rec" > "$S/swiftc_rec.txt" 2>&1; echo "rec swiftc exit $?" >> "$S/swiftc_rec.txt"; codesign --force -s - "$RUNNER_TEMP/rec" > /dev/null 2>&1 ) &
RECB=$!
clang -O1 -framework ApplicationServices drag/mouse2.c -o "$RUNNER_TEMP/m2" > "$S/compile.txt" 2>&1; echo "mouse2 exit $?" >> "$S/compile.txt"
clang -O1 -framework ApplicationServices -framework CoreFoundation drag/axdock.c -o "$RUNNER_TEMP/axdock" >> "$S/compile.txt" 2>&1; echo "axdock exit $?" >> "$S/compile.txt"
M="$RUNNER_TEMP/m2"; AXD="$RUNNER_TEMP/axdock"
sw_vers > "$S/os.txt"; system_profiler SPDisplaysDataType > "$S/display.txt" 2>&1
defaults read com.apple.universalaccess > "$S/ua_before.txt" 2>&1
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false 2>> "$LOG"; done
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >> "$LOG" 2>&1
defaults read com.apple.dock > "$S/dock_prefs_before.txt" 2>&1
python3 drag/flatwall.py "$S/wall_grey.png" 1024 768 128 128 128
python3 drag/wall.py "$S" >> "$LOG" 2>&1
wall() { osascript -e "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$1\")" >> "$LOG" 2>&1; sleep 2; }
wall "$S/wall_grey.png"
osascript -e 'tell application "Finder" to close every window' >> "$LOG" 2>&1
defaults write com.apple.dock autohide -bool false
killall Dock ControlCenter SystemUIServer NotificationCenter Spotlight WindowManager Finder >> "$LOG" 2>&1
sleep 8
osascript -l JavaScript -e 'ObjC.import("AppKit"); var w = $.NSWorkspace.sharedWorkspace; "RT=" + w.accessibilityDisplayShouldReduceTransparency + " RM=" + w.accessibilityDisplayShouldReduceMotion + " IC=" + w.accessibilityDisplayShouldIncreaseContrast' >> "$LOG" 2>&1
"$M" move 512 300 >> "$LOG"; sleep 1
# setting: $1 name, $2 largesize or "default"
setmag() {
  defaults write com.apple.dock magnification -bool true
  if [ "$2" = default ]; then defaults delete com.apple.dock largesize > /dev/null 2>&1; else defaults write com.apple.dock largesize -int $2; fi
  killall Dock; sleep 5
  DP=$(pgrep -x Dock | head -1)
  { echo "== $1"; defaults read com.apple.dock magnification; defaults read com.apple.dock largesize 2>&1; defaults read com.apple.dock tilesize 2>&1; } >> "$S/settings.txt"
  "$M" move 512 300 > /dev/null; sleep 1
  T 10 "$AXD" $DP > "$S/ax_rest_$1.txt" 2>&1
  screencapture -x -R0,520,1024,248 "$S/rest_$1.png"
  read DX DY DW DH <<< "$(awk -F'\t' '$1==0 && $2=="AXList" {printf "%d %d %d %d\n", $4, $5, $6, $7; exit}' "$S/ax_rest_$1.txt")"
  : ${DX:=35} ${DY:=702} ${DW:=954} ${DH:=56}
  echo "$1 dock list frame $DX $DY $DW $DH pid $DP" >> "$LOG"
}
sweep() {
  local n=$1 step=$2 Y=$(( DY + DH / 2 + 4 )) x0=$(( DX - 8 )) x1=$(( DX + DW + 8 )) k=0
  "$M" move $x0 $(( Y - 120 )) > /dev/null; sleep 0.5; "$M" move $x0 $Y > /dev/null; sleep 1.2
  echo "sweep $n y $Y from $x0 to $x1 step $step start $(ts)" >> "$LOG"
  for x in $(seq $x0 $step $x1); do
    "$M" move $x $Y > /dev/null; sleep 0.28
    screencapture -x -R0,520,1024,248 "$S/sweep/${n}_$(printf %04d $x).png" 2>> "$LOG"
    T 5 "$AXD" $DP > "$S/sweep/${n}_$(printf %04d $x).ax" 2>&1
    k=$((k+1))
  done
  echo "sweep $n frames $k end $(ts)" >> "$LOG"
  "$M" move 512 300 > /dev/null; sleep 1.2
}
setmag def default
sweep def 4
# a few stills over the bands wallpaper while magnified, for the glass look of the stretched platter
wall "$S/wall_bands.png"
for f in 0.2 0.5 0.8; do X=$(python3 -c "print(int($DX + $DW * $f))"); "$M" move $X $(( DY + DH / 2 + 4 )) > /dev/null; sleep 0.8; screencapture -x -R0,480,1024,288 "$S/bands_def_$f.png"; T 5 "$AXD" $DP > "$S/bands_def_$f.ax" 2>&1; done
"$M" move 512 300 > /dev/null; sleep 1
wall "$S/wall_grey.png"
# video: enter from above at 30%, rest, glide to 70% in 600 ms, rest, leave upward, re-enter fast at the far left
wait $RECB; cat "$S/swiftc_rec.txt" >> "$S/compile.txt"
if [ -x "$RUNNER_TEMP/rec" ]; then
  YD=$(( DY + DH / 2 + 4 )); XA=$(python3 -c "print(int($DX + $DW * 0.3))"); XB=$(python3 -c "print(int($DX + $DW * 0.7))"); XL=$(( DX + 30 ))
  ( T 40 "$RUNNER_TEMP/rec" "$S/vid/dockmag_def.mov" 13 > "$S/vid/dockmag_def.txt" 2>&1 ) & RP=$!
  sleep 1.8
  echo "vid enter $(ts)" >> "$LOG"; "$M" glide $XA $(( YD - 160 )) $XA $YD 250 >> "$LOG"; sleep 1.6
  echo "vid glide $(ts)" >> "$LOG"; "$M" glide $XA $YD $XB $YD 600 >> "$LOG"; sleep 1.6
  echo "vid leave $(ts)" >> "$LOG"; "$M" glide $XB $YD $XB $(( YD - 200 )) 200 >> "$LOG"; sleep 1.8
  echo "vid jump $(ts)" >> "$LOG"; "$M" move $XL $YD >> "$LOG"; sleep 1.6
  echo "vid out $(ts)" >> "$LOG"; "$M" move 512 300 >> "$LOG"; wait $RP
fi
setmag l80 80
sweep l80 4
defaults write com.apple.dock magnification -bool false; defaults delete com.apple.dock largesize > /dev/null 2>&1; killall Dock
echo "end $(ts)" >> "$LOG"
R="$RUNNER_TEMP/resD"; mkdir -p "$R/res"
( cd "$S" && zip -qr -9 "$R/res/dockmag.zip" . -x 'vid/*.mov' )
cp "$S"/vid/*.mov "$R/res/" 2>/dev/null; cp "$LOG" "$S/compile.txt" "$S/settings.txt" "$R/res/" 2>/dev/null
ls -la "$R/res" > "$R/res/files.txt"
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) dockmag" > "$R/res/run_id.txt"
gh auth setup-git > /dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b dockmag-results && git add res && git commit -qm "dockmag $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" dockmag-results ) || echo "publish failed"
exit 0
