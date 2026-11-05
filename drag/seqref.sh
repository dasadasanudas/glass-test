#!/bin/bash
# seqref: macOS 15 Sequoia references for MacWeb's Classic theme, on the runner named in lgx/runner.txt.
#   seqref.sh sys  -> drag/sysref.sh scenes (desk, Dock, menu bar, File menu, Control Center, Spotlight, NC over the bands/tiles/check
#                     wallpapers, light and dark, Reduce Transparency/Motion off) plus the Dock's AX frames, branch seq-sys
#   seqref.sh app  -> drag/appref.sh app windows (Finder views, Settings, Notes, Calculator, TextEdit, Terminal, Safari, Reminders,
#                     Calendar, Clock), branch seq-app
set +e
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
if [ "$1" = sys ]; then
  S="$RUNNER_TEMP/sys"; mkdir -p "$S"
  clang -O1 -framework ApplicationServices -framework CoreFoundation drag/axdock.c -o "$RUNNER_TEMP/axdock" > "$S/axdock_compile.txt" 2>&1
  clang -O1 -framework ApplicationServices drag/mouse2.c -o "$RUNNER_TEMP/m2" >> "$S/axdock_compile.txt" 2>&1
  for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false; done
  killall Dock; sleep 5
  DP=$(pgrep -x Dock | head -1)
  "$RUNNER_TEMP/m2" move 512 300 > /dev/null; sleep 1
  T 10 "$RUNNER_TEMP/axdock" $DP > "$S/ax_dock_rest.txt" 2>&1
  defaults read com.apple.dock > "$S/dock_prefs.txt" 2>&1
  # magnified frames at a few pointer positions (Sequoia's curve), then magnification back off
  defaults write com.apple.dock magnification -bool true; killall Dock; sleep 5; DP=$(pgrep -x Dock | head -1)
  read DX DY DW DH <<< "$(awk -F'\t' '$1==0 && $2=="AXList" {printf "%d %d %d %d\n", $4, $5, $6, $7; exit}' "$S/ax_dock_rest.txt")"
  : ${DX:=35} ${DY:=702} ${DW:=954} ${DH:=56}
  for f in 0.2 0.37 0.5 0.63 0.8; do X=$(python3 -c "print(int($DX + $DW * $f))"); "$RUNNER_TEMP/m2" move $X $(( DY + DH / 2 + 4 )) > /dev/null; sleep 0.9; T 10 "$RUNNER_TEMP/axdock" $DP > "$S/ax_dock_mag_$f.txt" 2>&1; screencapture -x -R0,480,1024,288 "$S/dock_mag_$f.png"; done
  "$RUNNER_TEMP/m2" move 512 300 > /dev/null; defaults write com.apple.dock magnification -bool false; killall Dock; sleep 4
  sed 's/drag-results/seq-sys/g' drag/sysref.sh > "$RUNNER_TEMP/seq_sys.sh"
  bash "$RUNNER_TEMP/seq_sys.sh"
else
  sed 's/drag-results/seq-app/g' drag/appref.sh > "$RUNNER_TEMP/seq_app.sh"
  bash "$RUNNER_TEMP/seq_app.sh"
fi
exit 0
