#!/bin/bash
# press: Tahoe toolbar glass buttons and window controls under real mouse presses (hover 0.6 s, press-hold 0.45 s, release),
# plus press-and-drag-off (cancel), in Finder, Safari, Notes and Reminders (light; Finder also dark). 60 fps ScreenCaptureKit
# video (drag/rec.swift), AX trees of each app (toolbar button frames), stills. Results: branch press-results.
set +e
( perl -e 'alarm shift; exec @ARGV' 300 swiftc -O -swift-version 5 drag/rec.swift -o "$RUNNER_TEMP/rec" > "$RUNNER_TEMP/swiftc_rec.txt" 2>&1; echo "rec swiftc exit $?" >> "$RUNNER_TEMP/swiftc_rec.txt"; codesign --force -s - "$RUNNER_TEMP/rec" > /dev/null 2>&1 ) &
RECB=$!
clang -O1 -framework ApplicationServices -framework CoreFoundation drag/axtree.c -o "$RUNNER_TEMP/axtree" > "$RUNNER_TEMP/axtree_cc.txt" 2>&1; echo "axtree exit $?" >> "$RUNNER_TEMP/axtree_cc.txt"
sed -n '1,/^# ---------------- 1. menu bar, light/p' drag/anim.sh > "$RUNNER_TEMP/anim_head.sh"
. "$RUNNER_TEMP/anim_head.sh"
kill $SWIFT 2>/dev/null
echo "head sourced S=$S" >> "$LOG"
rec() { ( T $(( $2 + 40 )) "$RUNNER_TEMP/rec" "$S/vid/$1.mov" "$2" > "$S/vid/$1.txt" 2>&1; echo "rec $1 exit $? $(ts)" >> "$LOG" ) & RP=$!; REND=$(( $(date +%s) + $2 + 20 )); echo "rec $1 start $(ts) len $2 el $(el)" >> "$LOG"; sleep 1.5; }
wait $RECB; cat "$RUNNER_TEMP/swiftc_rec.txt" "$RUNNER_TEMP/axtree_cc.txt" >> "$S/compile.txt"
AXT() { local P; P=$(pgrep -x "$1" | head -1); [ -n "$P" ] && T 40 "$RUNNER_TEMP/axtree" $P 12 > "$S/ax/$2.txt" 2>> "$LOG"; }
# toolbar candidates: buttons whose centre sits in the top 70 pt of the window (cx cy role subrole name w h enabled)
tb() { awk -F'\t' -v wy="$2" -v wx="$3" '($2=="AXButton"||$2=="AXMenuButton"||$2=="AXRadioButton"||$2=="AXCheckBox"||$2=="AXPopUpButton") && $15>=12 && $16>=12 && $15<=140 && $16<=64 { cy=$14+$16/2; cx=$13+$15/2; if (cy>wy && cy<wy+70 && cx>wx) { n=($4!=""?$4:($5!=""?$5:$7)); gsub(/[ \t]/,"_",n); printf "%d %d %s %s %s %.0f %.0f %s\n", cx, cy, $2, ($3==""?"-":$3), (n==""?"?":n), $15, $16, ($8==""?"?":$8) } }' "$S/ax/$1.txt" | sort -n -k1,1 -k2,2 | awk '!seen[$1" "$2]++'; }
press() { local x=$1 y=$2 n="$3"
  "$M" glide 520 430 $x $y 260 >> "$LOG"; sleep 0.6
  ev "press $n"; "$M" down $x $y >> "$LOG"; sleep 0.45; "$M" up $x $y >> "$LOG"; ev "release $n"; sleep 1.0
  code 53; code 53; "$M" glide $x $y 520 430 220 >> "$LOG"; sleep 0.4; }
off() { local x=$1 y=$2 n="$3"
  "$M" glide 520 430 $x $y 260 >> "$LOG"; sleep 0.6
  ev "pressoff $n"; "$M" down $x $y >> "$LOG"; sleep 0.4; "$M" glide $x $y $x $(( y + 110 )) 320 d >> "$LOG"; sleep 0.25; "$M" up $x $(( y + 110 )) >> "$LOG"; ev "releaseoff $n"; sleep 0.9; }
lights() { local f="$1" CX CY NX NY ZX ZY
  read CX CY <<< "$(awk -F'\t' '$3=="AXCloseButton" {printf "%d %d\n", $13+$15/2, $14+$16/2; exit}' "$S/ax/$f.txt")"
  read NX NY <<< "$(awk -F'\t' '$3=="AXMinimizeButton" {printf "%d %d\n", $13+$15/2, $14+$16/2; exit}' "$S/ax/$f.txt")"
  read ZX ZY <<< "$(awk -F'\t' '$3=="AXZoomButton"||$3=="AXFullScreenButton" {printf "%d %d\n", $13+$15/2, $14+$16/2; exit}' "$S/ax/$f.txt")"
  [ -z "$CX" ] && return
  ev "lights hover"; "$M" glide 520 430 $CX $CY 300 >> "$LOG"; sleep 0.9
  off $CX $CY close; [ -n "$NX" ] && off $NX $NY minimize; [ -n "$ZX" ] && off $ZX $ZY zoom; }
scene() { # process ax-name video-name
  local app="$1" f="$2" v="$3" N X Y R SR NM BW BH EN WX0 WY0
  AXT "$app" "$f"
  read WX0 WY0 <<< "$(awk -F'\t' '$2=="AXWindow" && $15>300 {printf "%d %d\n", $13, $14; exit}' "$S/ax/$f.txt")"; : ${WX0:=60} ${WY0:=60}
  tb "$f" $WY0 $WX0 > "$S/ax/${f}_tb.txt"; N=$(wc -l < "$S/ax/${f}_tb.txt" | tr -d ' '); echo "$f window $WX0,$WY0 buttons $N" >> "$LOG"; cat "$S/ax/${f}_tb.txt" >> "$LOG"
  shot "${f}_static"
  rec "$v" $(( N * 4 + 18 ))
  lights "$f"
  while read -r X Y R SR NM BW BH EN <&3; do
    case "$SR" in AXCloseButton|AXMinimizeButton|AXZoomButton|AXFullScreenButton) continue;; esac
    press $X $Y "$NM"
    case "$NM" in *idebar*) "$M" click $X $Y 80 >> "$LOG"; sleep 0.8;; esac
  done 3< "$S/ax/${f}_tb.txt"
  read X Y R SR NM BW BH EN <<< "$(awk '$4!="AXCloseButton" && $4!="AXMinimizeButton" && $4!="AXZoomButton" && $4!="AXFullScreenButton" && $8=="1"' "$S/ax/${f}_tb.txt" | head -1)"
  [ -n "$X" ] && off $X $Y "$NM"
  recwait; shot "${f}_after"
}
MODE=light
front Finder; sleep 1
scene Finder ax_finder press_finder_light
osa 'tell application "Safari" to activate'; sleep 7; code 53; front Safari; place Safari 60 60 964 644; sleep 1.5
scene Safari ax_safari press_safari_light
osa 'tell application "Safari" to quit'; sleep 1.5
osa 'tell application "Notes" to activate'; sleep 7; code 36; sleep 1; code 53; sleep 1; front Notes; place Notes 60 60 964 644; sleep 1.5
scene Notes ax_notes press_notes_light
osa 'tell application "Notes" to quit'; sleep 1.5
osa 'tell application "Reminders" to activate'; sleep 7; code 36; sleep 1; code 53; sleep 1; front Reminders; place Reminders 60 60 964 644; sleep 1.5
scene Reminders ax_reminders press_reminders_light
osa 'tell application "Reminders" to quit'; sleep 1.5
MODE=dark; dark true; front Finder; sleep 1
scene Finder ax_finder_dark press_finder_dark
dark false
flags; echo "end el $(el)" >> "$LOG"
R="$RUNNER_TEMP/resP"; mkdir -p "$R/res"
( cd "$S" && zip -qr -9 "$R/res/press-extra.zip" . -x 'vid/*.mov' )
cp "$S"/vid/*.mov "$R/res/" 2>/dev/null; cp "$LOG" "$S/compile.txt" "$R/res/" 2>/dev/null
ls -la "$R/res" > "$R/res/files.txt"; cat "$R/res/files.txt"
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) press el $(el)" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b press-results && git add res && git commit -qm "press $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" press-results ) || echo "publish failed"
exit 0
