#!/bin/bash
# LGX capture driver (called by .github/workflows/lgx-capture.yml). No set -e on purpose.
OUT="$RUNNER_TEMP/lgx-cap"; mkdir -p "$OUT"
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
defaults write com.apple.universalaccess reduceTransparency -bool false || true
clang -fno-objc-arc -fobjc-exceptions -O1 -Wno-deprecated-declarations -Wno-objc-multiple-method-names \
  -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework CoreMedia \
  -framework ImageIO -framework CoreGraphics lgx/capture.m -o "$RUNNER_TEMP/cap" > "$OUT/compile.txt" 2>&1
echo "clang exit $?" >> "$OUT/compile.txt"; cat "$OUT/compile.txt"
codesign -s - -f "$RUNNER_TEMP/cap" || true
{ sw_vers; system_profiler SPDisplaysDataType; ls -la "/System/Library/Desktop Pictures/.wallpapers/Tahoe Day/"; } > "$OUT/system.txt" 2>&1
MODES="${LGX_MODES:-$(cat lgx/modes.txt 2>/dev/null || echo 'probe:move,detach,clone full')}"
S=none
if [ -x "$RUNNER_TEMP/cap" ]; then
  for TRY in move detach clone; do
    mkdir -p "$OUT/try-$TRY"
    T 100 "$RUNNER_TEMP/cap" "$OUT/try-$TRY" "$TRY" probe 90 > "$OUT/try-$TRY/stdout.txt" 2>&1; echo "exit $?" >> "$OUT/try-$TRY/stdout.txt"
    if grep -q '^DRAW .*glass_background' "$OUT/try-$TRY/log.txt" 2>/dev/null; then S=$TRY; break; fi
  done
fi
echo "$S" > "$OUT/strategy.txt"; echo "strategy=$S"
if [ "$S" != none ]; then
  mkdir -p "$OUT/full"
  T 560 "$RUNNER_TEMP/cap" "$OUT/full" "$S" full 540 > "$OUT/full/stdout.txt" 2>&1; echo "exit $?" >> "$OUT/full/stdout.txt"
fi
{
  echo "strategy=$S"; cat "$OUT/compile.txt"
  for d in "$OUT"/try-* "$OUT/full"; do
    [ -d "$d" ] || continue; echo "== $d"; tail -3 "$d/stdout.txt" 2>/dev/null
    echo "draws: $(grep -c '^DRAW' "$d/log.txt" 2>/dev/null)  frames: $(grep -c '^FRAME .* end' "$d/log.txt" 2>/dev/null)"
    grep -E '^(DEVICE|HOOK|FRAME|SCENE|TAHOE|STRIP|READ fail|READ skip|WATCHDOG|DONE|clone)' "$d/log.txt" 2>/dev/null | head -80
    grep -oE '^DRAW [^ ]+ d[0-9]+ e[0-9]+ [^|]*' "$d/log.txt" 2>/dev/null | sed -E 's/^DRAW [^ ]+ d[0-9]+ e[0-9]+ //; s/v[0-9]+\+[0-9]+//; s/pso=0x[0-9a-f]+//' | sort | uniq -c | sort -rn | head -40
  done
  du -sh "$OUT"/* 2>/dev/null
} > "$OUT/summary.txt" 2>&1
cat "$OUT/summary.txt"
# publish text results to the lgx-results branch (read back through the GitHub API)
R="$RUNNER_TEMP/res"; mkdir -p "$R/res"
cp "$OUT/summary.txt" "$OUT/compile.txt" "$OUT/system.txt" "$R/res/" 2>/dev/null
for d in "$OUT"/try-* "$OUT/full"; do [ -d "$d" ] || continue; n=$(basename "$d"); head -c 400000 "$d/log.txt" > "$R/res/$n-log-head.txt" 2>/dev/null; tail -c 20000 "$d/stdout.txt" > "$R/res/$n-stdout.txt" 2>/dev/null; done
echo "$GITHUB_RUN_ID $(git rev-parse HEAD)" > "$R/res/run_id.txt"
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b lgx-results && git add res && git commit -qm "lgx capture $GITHUB_RUN_ID" && git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" lgx-results ) || echo "publish failed"
exit 0
