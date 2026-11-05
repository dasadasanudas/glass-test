#!/bin/bash
# syms: SF Symbols as vector PDFs (all names at regular, plus a toolbar shortlist at 9 weights x 3 scales). Results: branch syms-results.
set +e
S="$RUNNER_TEMP/syms"; mkdir -p "$S"; LOG="$S/log.txt"
sw_vers >> "$LOG" 2>&1
find /System/Library -name 'name_availability.plist' 2>/dev/null > "$S/plists.txt"; cat "$S/plists.txt" >> "$LOG"
P=$(grep -m1 CoreGlyphs "$S/plists.txt"); [ -z "$P" ] && P=$(head -1 "$S/plists.txt")
echo "plist $P" >> "$LOG"
perl -e 'alarm shift; exec @ARGV' 300 swiftc -O -swift-version 5 drag/syms.swift -o "$RUNNER_TEMP/syms_bin" > "$S/swiftc.txt" 2>&1; echo "swiftc exit $?" >> "$S/swiftc.txt"; cat "$S/swiftc.txt" >> "$LOG"
perl -e 'alarm shift; exec @ARGV' 420 "$RUNNER_TEMP/syms_bin" "$S" "$P" >> "$LOG" 2>&1; echo "syms exit $?" >> "$LOG"
for f in "$S"/*.pdf; do echo "$f $(stat -f %z "$f") images $(grep -a -c '/Subtype /Image' "$f") fonts $(grep -a -c '/Type /Font' "$f")" >> "$LOG"; done
cat "$LOG"
R="$RUNNER_TEMP/resS"; mkdir -p "$R/res"
( cd "$S" && zip -qr -9 "$R/res/syms.zip" . )
cp "$LOG" "$R/res/" 2>/dev/null
ls -la "$R/res" > "$R/res/files.txt"; cat "$R/res/files.txt"
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) syms" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b syms-results && git add res && git commit -qm "syms $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" syms-results ) || echo "publish failed"
mkdir -p "$RUNNER_TEMP/lgx-cap"; cp "$LOG" "$RUNNER_TEMP/lgx-cap/" 2>/dev/null
exit 0
