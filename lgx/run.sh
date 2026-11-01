#!/bin/bash
# LGX capture driver (called by .github/workflows/lgx-capture.yml). No set -e on purpose.
OUT="$RUNNER_TEMP/lgx-cap"; mkdir -p "$OUT"
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
defaults write com.apple.universalaccess reduceTransparency -bool false || true
python3 lgx/patch_cap.py lgx/capture.m > "$OUT/patch.txt" 2>&1; cat "$OUT/patch.txt"
clang -fno-objc-arc -fobjc-exceptions -O1 -Wno-deprecated-declarations -Wno-objc-multiple-method-names \
  -framework AppKit -framework QuartzCore -framework Metal -framework AVFoundation -framework CoreMedia \
  -framework ImageIO -framework CoreGraphics lgx/capture.m -o "$RUNNER_TEMP/cap" > "$OUT/compile.txt" 2>&1
echo "clang exit $?" >> "$OUT/compile.txt"; cat "$OUT/compile.txt"
codesign -s - -f "$RUNNER_TEMP/cap" || true
{ sw_vers; system_profiler SPDisplaysDataType; ls -la "/System/Library/Desktop Pictures/.wallpapers/Tahoe Day/"; } > "$OUT/system.txt" 2>&1
MODES="${LGX_MODES:-$(cat lgx/modes.txt 2>/dev/null || echo 'probe:move,detach,clone full')}"
S=none
if [ -x "$RUNNER_TEMP/cap" ]; then
  S=move; mkdir -p "$OUT/full"
  T 560 "$RUNNER_TEMP/cap" "$OUT/full" "$S" full 540 > "$OUT/full/stdout.txt" 2>&1; echo "exit $?" >> "$OUT/full/stdout.txt"
fi
echo "$S" > "$OUT/strategy.txt"; echo "strategy=$S"
# independent extraction of Apple's shader modules (QuartzCore default.metallib)
T 900 brew install llvm > "$OUT/brew.txt" 2>&1; LD="$(brew --prefix llvm 2>/dev/null)/bin/llvm-dis"; echo "llvm-dis: $LD" >> "$OUT/brew.txt"; ls -la "$LD" >> "$OUT/brew.txt" 2>&1
T 900 python3 lgx/air_dump.py /System/Library/Frameworks/QuartzCore.framework/Versions/A/Resources/default.metallib "$OUT/air" "$LD" > "$OUT/air_log.txt" 2>&1; echo "air exit $?" >> "$OUT/air_log.txt"
# shrink the artifact: big render-target dumps duplicate the frame PNGs; 16-bit 4K wallpaper -> JPEG
F="$OUT/full"
if [ -d "$F" ]; then
  find "$F/tex" -name '*_rt_*' -size +600k -delete 2>/dev/null
  for f in "$F"/img/tahoe_t0_full.png; do [ -f "$f" ] && sips -s format jpeg -s formatOptions 95 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 && rm -f "$f"; done
fi
{
  echo "strategy=$S"; cat "$OUT/compile.txt"
  for d in "$OUT"/try-* "$OUT/full"; do
    [ -d "$d" ] || continue; echo "== $d"; tail -3 "$d/stdout.txt" 2>/dev/null
    echo "draws: $(grep -c '^DRAW' "$d/log.txt" 2>/dev/null)  frames: $(grep -c '^FRAME .* end' "$d/log.txt" 2>/dev/null)"
    grep -E '^(DEVICE|FRAME|SCENE|TAHOE|STRIP|READ fail|READ skip|WATCHDOG|DONE|clone|NOHL|LIBCLASS)' "$d/log.txt" 2>/dev/null | head -80
    grep -oE '^DRAW [^ ]+ d[0-9]+ e[0-9]+ [^|]*' "$d/log.txt" 2>/dev/null | sed -E 's/^DRAW [^ ]+ d[0-9]+ e[0-9]+ //; s/v[0-9]+\+[0-9]+//; s/pso=0x[0-9a-f]+//' | sort | uniq -c | sort -rn | head -40
  done
  du -sh "$OUT"/* 2>/dev/null
} > "$OUT/summary.txt" 2>&1
cat "$OUT/summary.txt"
# publish text results to the lgx-results branch (read back through the GitHub API)
R="$RUNNER_TEMP/res"; mkdir -p "$R/res"
cp "$OUT/summary.txt" "$OUT/compile.txt" "$OUT/system.txt" "$OUT/patch.txt" "$OUT/brew.txt" "$OUT/air_log.txt" "$R/res/" 2>/dev/null
[ -f "$OUT/air/functions.txt" ] && cp "$OUT/air/functions.txt" "$R/res/air_functions.txt"
[ -d "$OUT/air" ] && ( cd "$OUT/air" && zip -qr -9 "$R/res/air.zip" . )
for d in "$OUT"/try-* "$OUT/full"; do [ -d "$d" ] || continue; n=$(basename "$d"); head -c 400000 "$d/log.txt" > "$R/res/$n-log-head.txt" 2>/dev/null; tail -c 20000 "$d/stdout.txt" > "$R/res/$n-stdout.txt" 2>/dev/null; done
echo "$GITHUB_RUN_ID $(git rev-parse HEAD)" > "$R/res/run_id.txt"
# full capture as one zip on the public results branch (readable without a login)
if [ -d "$OUT/full" ]; then ( cd "$OUT/full" && zip -qr -9 "$R/res/cap-full.zip" . ); ls -la "$R/res/cap-full.zip"; fi
if [ -f "$R/res/cap-full.zip" ] && [ $(stat -f %z "$R/res/cap-full.zip") -gt 90000000 ]; then rm -f "$R/res/cap-full.zip"; ( cd "$OUT/full" && zip -qr -9 "$R/res/cap-full.zip" . -x 'tex/*.png' ); fi
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b lgx-results && git add res && git commit -qm "lgx capture $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" lgx-results ) || echo "publish failed"
for d in "$OUT"/try-* "$OUT/full"; do [ -f "$d/log.txt" ] && gzip -9 -f "$d/log.txt"; done
du -sh "$OUT" "$OUT"/full/* 2>/dev/null
exit 0
