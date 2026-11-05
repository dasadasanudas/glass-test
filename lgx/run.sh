#!/bin/bash
# Capture driver (run-7 scenes). Edit patch file / scene list, then push under lgx/ to run a capture.
# A commit whose subject starts with [drag] runs drag/run.sh instead (results on the drag-results branch).
# A commit whose subject starts with [live] runs a 9-minute self-test of live/start.sh (status on live-status).
# A commit whose subject starts with [uiax] runs drag/uiax.sh (menus, CC, Spotlight, NC AX + icons, branch uiax-<macOS major>).
if git log -1 --format=%s | grep -q '^\[live\]'; then
  MINUTES=9 bash live/start.sh
  exit 0
fi
if git log -1 --format=%s | grep -q '^\[uiax\]'; then
  bash drag/uiax.sh
  mkdir -p "$RUNNER_TEMP/lgx-cap"; cp "$RUNNER_TEMP/uiax/log.txt" "$RUNNER_TEMP/lgx-cap/" 2>/dev/null
  exit 0
fi
if git log -1 --format=%s | grep -q '^\[drag\]'; then
  bash drag/run.sh
  mkdir -p "$RUNNER_TEMP/lgx-cap"; cp -R "$RUNNER_TEMP/drag/." "$RUNNER_TEMP/lgx-cap/" 2>/dev/null
  exit 0
fi
OUT="$RUNNER_TEMP/lgx-cap"; mkdir -p "$OUT"
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
defaults write com.apple.universalaccess reduceTransparency -bool false || true
python3 lgx/patch7.py lgx/capture.m > "$OUT/patch.txt" 2>&1; cat "$OUT/patch.txt"
clang -fno-objc-arc -fobjc-exceptions -O1 -Wno-deprecated-declarations -Wno-objc-multiple-method-names \
  -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework CoreMedia \
  -framework ImageIO -framework CoreGraphics lgx/capture.m -o "$RUNNER_TEMP/cap" > "$OUT/compile.txt" 2>&1
echo "clang exit $?" >> "$OUT/compile.txt"; cat "$OUT/compile.txt"
codesign -s - -f "$RUNNER_TEMP/cap" || true
S=none
if [ -x "$RUNNER_TEMP/cap" ]; then
  S=move; mkdir -p "$OUT/full"
  T 700 "$RUNNER_TEMP/cap" "$OUT/full" "$S" full 680 > "$OUT/full/stdout.txt" 2>&1; echo "exit $?" >> "$OUT/full/stdout.txt"
fi
R="$RUNNER_TEMP/res"; mkdir -p "$R/res"
if [ -d "$OUT/full" ]; then ( cd "$OUT/full" && zip -qr -9 "$R/res/cap-full.zip" . ); fi
echo "$GITHUB_RUN_ID $(git rev-parse HEAD)" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b lgx-results7 && git add res && git commit -qm "lgx capture $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" lgx-results7 ) || echo "publish failed"
exit 0
