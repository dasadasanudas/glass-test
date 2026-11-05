#!/bin/bash
# dockgeo: how the real macOS 26 Dock sizes itself. At 1920x1080 (room to spare) and 1280x720, for tilesize unset
# (system default) and 32, 64, 96, 128: the Dock's AX tree (list + every item frame) and a still of the bottom band.
# Plus one magnified still per size with the pointer at the Dock centre. Results: branch dockgeo-results.
set +e
S="$RUNNER_TEMP/dg"; mkdir -p "$S"; LOG="$S/log.txt"
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
clang -O1 -framework ApplicationServices drag/mouse2.c -o "$RUNNER_TEMP/m2" > "$S/compile.txt" 2>&1
clang -O1 -framework ApplicationServices -framework CoreFoundation drag/axdock.c -o "$RUNNER_TEMP/axdock" >> "$S/compile.txt" 2>&1
M="$RUNNER_TEMP/m2"; AXD="$RUNNER_TEMP/axdock"
which displayplacer > /dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 T 240 brew install displayplacer > "$S/dp_install.txt" 2>&1
ID=$(displayplacer list 2>/dev/null | grep -m1 'Persistent screen id:' | awk '{print $4}')
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false; done
python3 drag/flatwall.py "$S/wall_grey.png" 1920 1200 128 128 128
osascript -e "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$S/wall_grey.png\")" >> "$LOG" 2>&1
osascript -e 'tell application "Finder" to close every window' >> "$LOG" 2>&1
defaults write com.apple.dock autohide -bool false
defaults write com.apple.dock magnification -bool true; defaults delete com.apple.dock largesize > /dev/null 2>&1
killall Dock ControlCenter SystemUIServer Finder >> "$LOG" 2>&1; sleep 6
for RES in 1920x1080 1280x720; do
  W=${RES%x*}; H=${RES#*x}
  displayplacer "id:$ID res:$RES hz:60 color_depth:7 enabled:true scaling:off origin:(0,0) degree:0" >> "$LOG" 2>&1; sleep 4
  echo "res $RES now $(displayplacer list 2>/dev/null | grep -m1 'Resolution:')" >> "$LOG"
  for TS in default 32 64 96 128; do
    if [ $TS = default ]; then defaults delete com.apple.dock tilesize > /dev/null 2>&1; else defaults write com.apple.dock tilesize -int $TS; fi
    killall Dock; sleep 4
    DP=$(pgrep -x Dock | head -1)
    "$M" move $(( W / 2 )) $(( H / 3 )) > /dev/null; sleep 1
    T 10 "$AXD" $DP > "$S/ax_${RES}_${TS}.txt" 2>&1
    screencapture -x -R0,$(( H - 260 )),$W,260 "$S/rest_${RES}_${TS}.png"
    read DX DY DW DH <<< "$(awk -F'\t' '$1==0 && $2=="AXList" {printf "%d %d %d %d\n", $4, $5, $6, $7; exit}' "$S/ax_${RES}_${TS}.txt")"
    "$M" move $(( DX + DW / 2 )) $(( DY + DH / 2 + 4 )) > /dev/null; sleep 0.9
    screencapture -x -R0,$(( H - 260 )),$W,260 "$S/mag_${RES}_${TS}.png"
    T 10 "$AXD" $DP > "$S/axmag_${RES}_${TS}.txt" 2>&1
    echo "$RES $TS list $DX $DY $DW $DH" >> "$LOG"
  done
done
defaults delete com.apple.dock tilesize > /dev/null 2>&1; defaults write com.apple.dock magnification -bool false; killall Dock
R="$RUNNER_TEMP/resG"; mkdir -p "$R/res"
( cd "$S" && zip -qr -9 "$R/res/dockgeo.zip" . )
cp "$LOG" "$R/res/"
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) dockgeo" > "$R/res/run_id.txt"
gh auth setup-git > /dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b dockgeo-results && git add res && git commit -qm "dockgeo $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" dockgeo-results ) || echo "publish failed"
exit 0
