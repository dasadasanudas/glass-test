#!/bin/bash
# LGX capture driver, run 5 (called by .github/workflows/lgx-capture.yml). No set -e on purpose.
OUT="$RUNNER_TEMP/lgx-cap"; mkdir -p "$OUT"
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
defaults write com.apple.universalaccess reduceTransparency -bool false || true
python3 lgx/patch5.py lgx/capture.m > "$OUT/patch.txt" 2>&1; cat "$OUT/patch.txt"
clang -fno-objc-arc -fobjc-exceptions -O1 -Wno-deprecated-declarations -Wno-objc-multiple-method-names \
  -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework CoreMedia \
  -framework ImageIO -framework CoreGraphics lgx/capture.m -o "$RUNNER_TEMP/cap" > "$OUT/compile.txt" 2>&1
echo "clang exit $?" >> "$OUT/compile.txt"; cat "$OUT/compile.txt"
codesign -s - -f "$RUNNER_TEMP/cap" || true
{ sw_vers; system_profiler SPDisplaysDataType; } > "$OUT/system.txt" 2>&1
S=none
if [ -x "$RUNNER_TEMP/cap" ]; then
  S=move; mkdir -p "$OUT/full"
  T 700 "$RUNNER_TEMP/cap" "$OUT/full" "$S" full 680 > "$OUT/full/stdout.txt" 2>&1; echo "exit $?" >> "$OUT/full/stdout.txt"
fi
echo "$S" > "$OUT/strategy.txt"; echo "strategy=$S"
F="$OUT/full"
if [ -d "$F" ]; then
  find "$F/tex" -name '*_rt_*' -size +600k -delete 2>/dev/null
fi
{
  echo "strategy=$S"; cat "$OUT/compile.txt"
  for d in "$OUT/full"; do
    [ -d "$d" ] || continue; echo "== $d"; tail -3 "$d/stdout.txt" 2>/dev/null
    echo "draws: $(grep -c '^DRAW' "$d/log.txt" 2>/dev/null)  frames: $(grep -c '^FRAME .* end' "$d/log.txt" 2>/dev/null)  scenes: $(grep -c '^SCENE' "$d/log.txt" 2>/dev/null)"
    grep -E '^(DEVICE|TAHOE|REGION|READ fail|READ skip|WATCHDOG|DONE|FCVCLASS|BUFDUMP|NOISE|APPEARANCE)' "$d/log.txt" 2>/dev/null | head -80
    grep -c '^FCV ' "$d/log.txt"
    grep '^SCENE' "$d/log.txt" | tail -3
  done
  du -sh "$OUT"/* "$F"/* 2>/dev/null
} > "$OUT/summary.txt" 2>&1
cat "$OUT/summary.txt"
R="$RUNNER_TEMP/res"; mkdir -p "$R/res"
cp "$OUT/summary.txt" "$OUT/compile.txt" "$OUT/system.txt" "$OUT/patch.txt" "$R/res/" 2>/dev/null
for d in "$OUT/full"; do [ -d "$d" ] || continue; n=$(basename "$d"); head -c 400000 "$d/log.txt" > "$R/res/$n-log-head.txt" 2>/dev/null; tail -c 20000 "$d/stdout.txt" > "$R/res/$n-stdout.txt" 2>/dev/null; done
echo "$GITHUB_RUN_ID $(git rev-parse HEAD)" > "$R/res/run_id.txt"
if [ -d "$OUT/full" ]; then ( cd "$OUT/full" && zip -qr -9 "$R/res/cap-full.zip" . ); ls -la "$R/res/cap-full.zip"; fi
if [ -f "$R/res/cap-full.zip" ] && [ $(stat -f %z "$R/res/cap-full.zip") -gt 95000000 ]; then rm -f "$R/res/cap-full.zip"; ( cd "$OUT/full" && zip -qr -9 "$R/res/cap-full.zip" . -x 'tex/*_ft*.png' -x 'tex/*_L[1-9]_*' ); ls -la "$R/res/cap-full.zip"; fi
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b lgx-results && git add res && git commit -qm "lgx capture $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" lgx-results ) || echo "publish failed"
gzip -9 -f "$OUT/full/log.txt" 2>/dev/null
du -sh "$OUT" 2>/dev/null
exit 0
