#!/bin/bash
# System UI references with Reduce Transparency and Reduce Motion OFF for every process. The runner image ships both ON
# (actions/runner-images configure-system.sh) and the system UI (Dock, Control Center, menu bar, Spotlight) reads them at launch,
# so a defaults write alone only reaches newly launched apps: write the prefs, then restart those processes.
# Scenes over three known wallpapers (flat bands, 32 pt colour tiles, 16 pt checker), light and dark: desktop + Dock, Finder's
# File menu, Control Center, Spotlight (empty and typed), Notification Center. Region shots keep the zip small.
set +e
S="$RUNNER_TEMP/sys"; mkdir -p "$S"; LOG="$S/log.txt"
sw_vers > "$S/os.txt"; system_profiler SPDisplaysDataType > "$S/display.txt" 2>&1
defaults read com.apple.universalaccess > "$S/ua_before.txt" 2>&1
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false 2>> "$LOG"; done
defaults read com.apple.universalaccess > "$S/ua_after.txt" 2>&1
python3 drag/wall.py "$S" >> "$LOG" 2>&1
killall Dock ControlCenter SystemUIServer NotificationCenter Spotlight WindowManager Finder >> "$LOG" 2>&1
sleep 8
flags() { osascript -l JavaScript -e 'ObjC.import("AppKit"); var w = $.NSWorkspace.sharedWorkspace; "RT=" + w.accessibilityDisplayShouldReduceTransparency + " RM=" + w.accessibilityDisplayShouldReduceMotion + " IC=" + w.accessibilityDisplayShouldIncreaseContrast' >> "$LOG" 2>&1; }
flags
osascript -e 'tell application "System Events" to tell process "ControlCenter" to get description of every menu bar item of menu bar 1' >> "$LOG" 2>&1
esc() { osascript -e 'tell application "System Events" to key code 53' >> "$LOG" 2>&1; sleep 0.8; }
dark() { osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1" >> "$LOG" 2>&1; sleep 3; }
wall() { osascript -e "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$1\")" >> "$LOG" 2>&1; sleep 2.5; }
shot() { screencapture -x -R "$2" "$S/$1.png" 2>> "$LOG"; }
scene() {
  local t="$1"
  osascript -e 'tell application "Finder" to close every window' >> "$LOG" 2>&1
  osascript -e 'tell application "Finder" to activate' >> "$LOG" 2>&1; sleep 1.5
  if [ "$2" = full ]; then screencapture -x "$S/desk_$t.png"; else shot "dock_$t" "0,680,1024,88"; shot "bar_$t" "0,0,1024,40"; fi
  osascript -e 'tell application "System Events" to tell process "Dock" to get {position, size} of list 1' > "$S/dockframe_$t.txt" 2>&1
  osascript -e 'tell application "System Events" to tell process "Finder" to click menu bar item "File" of menu bar 1' >> "$LOG" 2>&1 &
  sleep 2; shot "menu_$t" "0,0,520,520"; esc
  osascript -e 'tell application "System Events" to tell process "ControlCenter" to click (first menu bar item of menu bar 1 whose description contains "Control")' >> "$LOG" 2>&1 &
  sleep 2.5; shot "cc_$t" "640,0,384,640"; esc
  osascript -e 'tell application "System Events" to keystroke space using command down' >> "$LOG" 2>&1; sleep 2
  shot "spot0_$t" "100,30,824,560"
  osascript -e 'tell application "System Events" to keystroke "calc"' >> "$LOG" 2>&1; sleep 2
  shot "spot_$t" "100,30,824,560"; esc; esc
  if [ "$2" = full ]; then
    osascript -e 'tell application "System Events" to tell process "ControlCenter" to click (first menu bar item of menu bar 1 whose description contains "Clock")' >> "$LOG" 2>&1 &
    sleep 2.5; shot "nc_$t" "600,0,424,768"; esc
  fi
  echo "scene $t done $(date +%T)" >> "$LOG"
}
for w in bands tiles check; do
  wall "$S/wall_$w.png"
  for m in light dark; do
    [ $m = dark ] && dark true || dark false
    scene "${w}_$m" $([ $w = bands ] && echo full)
  done
done
dark false
flags
( cd "$S" && zip -qr -9 "$RUNNER_TEMP/sysref.zip" . )
R="$RUNNER_TEMP/res0"; mkdir -p "$R/res"; cp "$RUNNER_TEMP/sysref.zip" "$LOG" "$R/res/" 2>/dev/null
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) sysref" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b drag-results && git add res && git commit -qm "sysref $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" drag-results ) || echo "publish failed"
exit 0
