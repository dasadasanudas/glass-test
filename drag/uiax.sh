#!/bin/bash
# uiax: accessibility dumps + full-screen shots of the system UI on the runner named in lgx/runner.txt (macOS 15 or 26), for MacWeb.
#   menus: every Finder menu bar menu (items with enabled state, shortcut char/modifiers/glyph, mark, frame), File/View/Go again
#          with a Finder window open; light and dark full-screen shots of each open menu
#   Control Center, Spotlight (empty, typed "calc"), Notification Center: AX trees + full-screen shots, light and dark
#   menu bar extras: ControlCenter / SystemUIServer / Spotlight trees (frames of the right-side items)
#   icons: 256 px sRGB PNGs of the system apps, folders, document types and Trash from NSWorkspace (drag/icons.swift)
# Reduce Transparency / Motion / Contrast off (system UI restarted), wallpaper = the 32 pt tile test image. Branch uiax-<major>.
set +e
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
S="$RUNNER_TEMP/uiax"; mkdir -p "$S/ax" "$S/shots" "$S/icons"; LOG="$S/log.txt"
sw_vers > "$S/os.txt"; V=$(sw_vers -productVersion | cut -d. -f1)
clang -O1 -framework ApplicationServices -framework CoreFoundation drag/axtree.c -o "$RUNNER_TEMP/axtree" > "$S/compile.txt" 2>&1; echo "axtree $?" >> "$S/compile.txt"
swiftc -O drag/icons.swift -o "$RUNNER_TEMP/icons" >> "$S/compile.txt" 2>&1; echo "icons $?" >> "$S/compile.txt"
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false; done
python3 drag/wall.py "$S" >> "$LOG" 2>&1
killall Dock ControlCenter SystemUIServer NotificationCenter Spotlight WindowManager Finder >> "$LOG" 2>&1; sleep 8
osascript -l JavaScript -e 'ObjC.import("AppKit"); var w = $.NSWorkspace.sharedWorkspace; "RT=" + w.accessibilityDisplayShouldReduceTransparency + " RM=" + w.accessibilityDisplayShouldReduceMotion' >> "$LOG" 2>&1
osascript -e "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$S/wall_tiles.png\")" >> "$LOG" 2>&1; sleep 2
ICL="$S/icons/list.txt"; : > "$ICL"
for n in Finder Launchpad Apps Safari Messages Mail Maps Photos FaceTime Phone Calendar Contacts Reminders Notes Freeform TV Music News Podcasts Books "App Store" "System Settings" "iPhone Mirroring" Games Calculator TextEdit Terminal Preview Clock Weather Stocks Home "Font Book" Passwords Journal "Image Playground" "Photo Booth" "QuickTime Player" Chess Dictionary Stickies Tips Shortcuts Siri "Activity Monitor" "Disk Utility" Screenshot Automator "Image Capture" "Mission Control" "Time Machine" "Voice Memos" "Find My" "Keychain Access" Console "System Information" "Digital Color Meter" Grapher "Script Editor" "Audio MIDI Setup" "ColorSync Utility" Xcode; do
  for d in /System/Applications /System/Applications/Utilities /Applications /System/Cryptexes/App/System/Applications /System/Library/CoreServices /System/Library/CoreServices/Applications; do
    if [ -d "$d/$n.app" ]; then printf '%s\t%s\n' "$n" "$d/$n.app" >> "$ICL"; break; fi
  done
done
F=/tmp/uiaxf; mkdir -p "$F/Folder"; for e in txt md pdf png jpg zip html js py json mov mp3 rtf csv dmg; do touch "$F/a.$e"; printf '%s\t%s\n' "doc_$e" "$F/a.$e" >> "$ICL"; done
printf '%s\t%s\n' Downloads "$HOME/Downloads" Documents "$HOME/Documents" Desktop "$HOME/Desktop" Applications /Applications Home "$HOME" HD / Folder "$F/Folder" Library "$HOME/Library" TrashEmpty @NSTrashEmpty TrashFull @NSTrashFull Network @NSNetwork Computer @NSComputer Folder2 @NSFolder >> "$ICL"
T 150 "$RUNNER_TEMP/icons" "$S/icons" "$ICL" 256 > "$S/icons/log.txt" 2>&1
AX() { local P; P=$(pgrep -x "$1" | head -1); [ -n "$P" ] && T 40 "$RUNNER_TEMP/axtree" $P ${3:-14} > "$S/ax/$2.txt" 2>&1; }
esc() { osascript -e 'tell application "System Events" to key code 53' >> "$LOG" 2>&1; sleep 0.8; }
full() { screencapture -x "$S/shots/$1.png" 2>> "$LOG"; }
dark() { osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1" >> "$LOG" 2>&1; sleep 3; }
finder() { osascript -e 'tell application "Finder" to close every window' >> "$LOG" 2>&1; osascript -e 'tell application "Finder" to activate' >> "$LOG" 2>&1; sleep 1.5; }
menu() {
  ( T 12 osascript -e "tell application \"System Events\" to tell process \"Finder\" to click menu bar item \"$2\" of menu bar 1" >> "$LOG" 2>&1 & )
  sleep 2; [ "$3" = ax ] && AX Finder "menu_$1" 6; full "menu_$1"; esc; esc
  echo "menu $1 $(date +%T)" >> "$LOG"
}
for m in light dark; do
  [ $m = dark ] && dark true || dark false
  finder
  [ $m = light ] && { AX ControlCenter bar_ControlCenter 4; AX SystemUIServer bar_SystemUIServer 4; AX Spotlight bar_Spotlight 4; AX Finder finder_app 3; full desk_light; }
  for t in Apple Finder File Edit View Go Window Help; do menu "${t}_$m" "$t" $([ $m = light ] && echo ax); done
  osascript -e 'tell application "Finder" to make new Finder window' >> "$LOG" 2>&1; sleep 2.5
  for t in File View Go; do menu "${t}_win_$m" "$t" $([ $m = light ] && echo ax); done
  [ $m = light ] && { AX Finder finder_window 12; full finder_window_light; }
  finder
  ( T 12 osascript -e 'tell application "System Events" to tell process "ControlCenter" to click (first menu bar item of menu bar 1 whose description contains "Control")' >> "$LOG" 2>&1 & )
  sleep 2.5; [ $m = light ] && AX ControlCenter "cc" 16; full "cc_$m"; esc
  osascript -e 'tell application "System Events" to keystroke space using command down' >> "$LOG" 2>&1; sleep 2
  [ $m = light ] && AX Spotlight "spot0" 16; full "spot0_$m"
  osascript -e 'tell application "System Events" to keystroke "calc"' >> "$LOG" 2>&1; sleep 2.5
  [ $m = light ] && AX Spotlight "spot" 16; full "spot_$m"; esc; esc
  ( T 12 osascript -e 'tell application "System Events" to tell process "ControlCenter" to click (first menu bar item of menu bar 1 whose description contains "Clock")' >> "$LOG" 2>&1 & )
  sleep 2.5; [ $m = light ] && AX NotificationCenter "nc" 16; full "nc_$m"; esc
  echo "mode $m done $(date +%T)" >> "$LOG"
done
dark false
ls -la "$S/ax" >> "$LOG"; wc -l "$S"/ax/*.txt >> "$LOG"; tail -3 "$S/icons/log.txt" >> "$LOG"
( cd "$S" && zip -qr -9 "$RUNNER_TEMP/uiax.zip" . )
R="$RUNNER_TEMP/resu"; mkdir -p "$R/res"; cp "$RUNNER_TEMP/uiax.zip" "$LOG" "$S/compile.txt" "$R/res/" 2>/dev/null
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) uiax $V" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b "uiax-$V" && git add res && git commit -qm "uiax $V $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" "uiax-$V" ) || echo "publish failed"
exit 0
