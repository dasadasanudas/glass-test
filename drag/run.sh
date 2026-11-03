#!/bin/bash
# Drag-state capture driver. Push a change under drag/ to run it; results go to the drag-results branch.
OUT="$RUNNER_TEMP/drag"; mkdir -p "$OUT/shots"
sw_vers > "$OUT/os.txt"
defaults write com.apple.universalaccess reduceTransparency -bool false || true
clang -O1 -framework ApplicationServices drag/mouse.c -o "$RUNNER_TEMP/mouse" > "$OUT/compile.txt" 2>&1; echo "mouse clang exit $?" >> "$OUT/compile.txt"
APP="$RUNNER_TEMP/DragRef.app"; mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.probe.dragref</string>
<key>CFBundleName</key><string>DragRef</string>
<key>CFBundleExecutable</key><string>DragRef</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST_EOF
clang -fobjc-exceptions -fblocks -Wno-everything -framework AppKit -framework ApplicationServices drag/drag.m -o "$APP/Contents/MacOS/DragRef" >> "$OUT/compile.txt" 2>&1; echo "app clang exit $?" >> "$OUT/compile.txt"
cat "$OUT/compile.txt"
codesign --force -s - "$APP" > /dev/null 2>&1
( for i in $(seq 1 5); do osascript -e 'tell application id "dev.probe.dragref" to activate' > /dev/null 2>&1; sleep 2; done ) &
NUDGE=$!
open -n --stdout "$OUT/stdout.txt" --stderr "$OUT/stderr.txt" "$APP" --args "$OUT"
t=0; n=0; m=0
while [ $t -lt 17000 ]; do
  if [ -f "$OUT/req.txt" ]; then
    read CMD A B C < "$OUT/req.txt"
    case "$CMD" in
      SHOT) screencapture -x -o -l "$B" "$OUT/shots/$A.png" 2>> "$OUT/shot_err.txt"; n=$((n+1)) ;;
      SHOTR) screencapture -x -R "$B" "$OUT/shots/$A.png" 2>> "$OUT/shot_err.txt"; n=$((n+1)) ;;
      MOUSE) "$RUNNER_TEMP/mouse" "$A" "$B" "$C" >> "$OUT/mouse_log.txt" 2>&1; m=$((m+1)) ;;
    esac
    rm -f "$OUT/req.txt"; touch "$OUT/ack.txt"
  fi
  [ -f "$OUT/quit.txt" ] && break
  sleep 0.02; t=$((t+1))
done
kill $NUDGE 2>/dev/null; pkill -f DragRef
screencapture -x "$OUT/final_screen.png"
echo "shots $n mouse $m loops $t" > "$OUT/summary.txt"; cat "$OUT/summary.txt"; head -40 "$OUT/log.txt"
R="$RUNNER_TEMP/res"; mkdir -p "$R/res"
( cd "$OUT" && zip -qr -9 "$R/res/drag-cap.zip" . )
cp "$OUT/log.txt" "$OUT/compile.txt" "$OUT/summary.txt" "$OUT/mouse_log.txt" "$R/res/" 2>/dev/null
echo "$GITHUB_RUN_ID $(git rev-parse HEAD)" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b drag-results && git add res && git commit -qm "drag capture $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" drag-results ) || echo "publish failed"
exit 0
