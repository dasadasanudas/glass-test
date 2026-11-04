#!/bin/bash
# Glass merging capture: builds drag/merge.m (MergeRef.app) and serves its window-shot requests. Results: res/merge-cap.zip.
set +e
OUT="$RUNNER_TEMP/merge"; mkdir -p "$OUT/shots"; sw_vers > "$OUT/os.txt"
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false; done
osascript -l JavaScript -e 'ObjC.import("AppKit"); var w = $.NSWorkspace.sharedWorkspace; "RT=" + w.accessibilityDisplayShouldReduceTransparency + " RM=" + w.accessibilityDisplayShouldReduceMotion' > "$OUT/a11y.txt" 2>&1
APP="$RUNNER_TEMP/MergeRef.app"; mkdir -p "$APP/Contents/MacOS"
printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.probe.mergeref</string><key>CFBundleName</key><string>MergeRef</string><key>CFBundleExecutable</key><string>MergeRef</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>' > "$APP/Contents/Info.plist"
clang -fobjc-exceptions -fblocks -Wno-everything -framework AppKit -framework QuartzCore drag/merge.m -o "$APP/Contents/MacOS/MergeRef" > "$OUT/compile.txt" 2>&1; echo "merge clang exit $?" >> "$OUT/compile.txt"; cat "$OUT/compile.txt"
codesign --force -s - "$APP" > /dev/null 2>&1
( for i in 1 2 3 4; do sleep 1.5; osascript -e 'tell application id "dev.probe.mergeref" to activate' > /dev/null 2>&1; done ) &
open -n --stdout "$OUT/stdout.txt" --stderr "$OUT/stderr.txt" "$APP" --args "$OUT"
t=0; n=0
while [ $t -lt 22000 ]; do
  if [ -f "$OUT/req.txt" ]; then read CMD A B < "$OUT/req.txt"; [ "$CMD" = SHOT ] && screencapture -x -o -l "$B" "$OUT/shots/$A.png" 2>> "$OUT/shot_err.txt"; n=$((n+1)); rm -f "$OUT/req.txt"; touch "$OUT/ack.txt"; fi
  [ -f "$OUT/quit.txt" ] && break
  sleep 0.02; t=$((t+1))
done
pkill -f MergeRef; echo "shots $n loops $t" > "$OUT/summary.txt"; cat "$OUT/summary.txt"; tail -20 "$OUT/log.txt"
R="$RUNNER_TEMP/res"; mkdir -p "$R/res"; ( cd "$OUT" && zip -qr -9 "$R/res/merge-cap.zip" . ); cp "$OUT/log.txt" "$OUT/compile.txt" "$OUT/summary.txt" "$OUT/a11y.txt" "$R/res/" 2>/dev/null
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) merge" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b drag-results && git add res && git commit -qm "merge capture $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" drag-results ) || echo "publish failed"
exit 0
