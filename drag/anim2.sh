#!/bin/bash
# anim2: anim.sh's setup (prefs, walls, Finder window, menu bar positions, AnimRef build), then a ScreenCaptureKit
# recorder (drag/rec.swift) instead of screencapture -v, plus menu-area still bursts. Results: branch anim2-results.
# macOS bash 3.2 cannot source a process substitution, so the shared setup is written to a file first.
set +e
( perl -e 'alarm shift; exec @ARGV' 300 swiftc -O -swift-version 5 drag/rec.swift -o "$RUNNER_TEMP/rec" > "$RUNNER_TEMP/swiftc_rec.txt" 2>&1; echo "rec swiftc exit $?" >> "$RUNNER_TEMP/swiftc_rec.txt"; codesign --force -s - "$RUNNER_TEMP/rec" > /dev/null 2>&1 ) &
RECB=$!
sed -n '1,/^# ---------------- 1. menu bar, light/p' drag/anim.sh > "$RUNNER_TEMP/anim_head.sh"
. "$RUNNER_TEMP/anim_head.sh"
echo "head sourced S=$S" >> "$LOG"
mkdir -p "$S/burst"
rec() { ( T $(( $2 + 40 )) "$RUNNER_TEMP/rec" "$S/vid/$1.mov" "$2" > "$S/vid/$1.txt" 2>&1; echo "rec $1 exit $? $(ts)" >> "$LOG" ) & RP=$!; REND=$(( $(date +%s) + $2 + 20 )); echo "rec $1 start $(ts) len $2 el $(el)" >> "$LOG"; sleep 1.5; }
burst() { local n=$1 k=0; ( while [ $k -lt $2 ]; do screencapture -x -R0,0,1024,420 "$S/burst/${n}_$(printf %03d $k).png" 2>/dev/null; echo "$k $(ts)" >> "$S/burst/${n}.txt"; k=$((k+1)); done ) & }
wait $RECB; cat "$RUNNER_TEMP/swiftc_rec.txt" >> "$S/compile.txt"
# ---------------- 1. menu bar, light: open, switch, Escape, choose (blink + fade), click outside, Apple menu
rec menubar_light 26
ev "click File"; burst file_open 12; "$M" click $FX $FY 90 >> "$LOG"; sleep 1.4
ev "glide File to Edit"; "$M" glide $FX $FY $EX $EY 200 >> "$LOG"; sleep 1.0
ev "escape"; code 53; sleep 1.3
ev "click View"; "$M" click $VX $VY 90 >> "$LOG"; sleep 0.9; mi Finder View
read IX IY <<< "$(mic View 'as List')"; : ${IX:=$(( VX + 40 ))} ${IY:=$(( VY + 52 ))}
ev "hover as List"; "$M" glide $VX $VY $IX $IY 300 >> "$LOG"; sleep 0.5
ev "choose as List"; burst choose 12; "$M" click $IX $IY 70 >> "$LOG"; sleep 1.5
ev "click Go then outside"; "$M" click $GX $GY 90 >> "$LOG"; sleep 1.0; ev "outside"; "$M" click 30 430 60 >> "$LOG"; sleep 1.3
ev "Apple menu"; "$M" click $AX $AY 90 >> "$LOG"; sleep 1.2; ev "apple escape"; code 53; sleep 1.2
recwait; front Finder; cmdk 1
# ---------------- 2. system UI
rec sys_light 22
ev "CC open"; "$M" click $CCX $CCY 90 >> "$LOG"; sleep 1.5; ev "CC close"; "$M" click $CCX $CCY 90 >> "$LOG"; sleep 1.3
ev "Spotlight open"; osa 'tell application "System Events" to keystroke space using command down'; sleep 1.5; ev "Spotlight close"; code 53; sleep 0.4; code 53; sleep 1.2
ev "NC open"; "$M" click $CLX $CLY 90 >> "$LOG"; sleep 1.5; ev "NC close"; "$M" click $CLX $CLY 90 >> "$LOG"; sleep 1.3
if [ -n "$APX" ]; then ev "Apps open"; "$M" click $APX $APY 90 >> "$LOG"; sleep 2.0; ev "Apps close"; code 53; sleep 1.5; fi
recwait
# ---------------- 3. windows
front Finder
rec win_light 16
ev "new window"; cmdk n; sleep 1.6
ev "close window cmd-w"; cmdk w; sleep 1.5
T 15 osascript -l JavaScript "$S/btn.js" Finder > "$S/ax/btn.txt" 2>> "$LOG"
read MX MY <<< "$(awk -F'\t' '$1=="AXMinimizeButton"{printf "%d %d\n",$2+$4/2,$3+$5/2; exit}' "$S/ax/btn.txt")"
if [ -n "$MX" ]; then ev "minimize"; "$M" click $MX $MY 90 >> "$LOG"; sleep 2.2; T 15 osascript -l JavaScript "$S/dock.js" > "$S/ax/dock2.txt" 2>> "$LOG"; read RX RY <<< "$(dkc AXMinimizedWindowDockItem dock2.txt)"; [ -n "$RX" ] && { ev "restore"; "$M" click $RX $RY 90 >> "$LOG"; sleep 2.2; }; fi
recwait
# ---------------- 4. controls: selection change, track click, switch toggle, pop-up open/close
wait $SWIFT; HAVEAPP=0; [ -x "$APP/Contents/MacOS/AnimRef" ] && HAVEAPP=1
fr() { awk -v n="$1" '$1==n {print $2, $3, $4, $5; exit}' "$S/frames.txt"; }
if [ $HAVEAPP = 1 ]; then
  open -n "$APP" --args "$S"; for i in $(seq 1 40); do [ -f "$S/frames.txt" ] && break; sleep 0.5; done; front AnimRef; sleep 4
  read SX SY SW SH <<< "$(fr seg1)"; read LX LY LW LH <<< "$(fr slider1)"; read WX2 WY2 WW2 WH2 <<< "$(fr switch1)"; read PX PY PW PH <<< "$(fr pop1)"; read UX UY UW UH <<< "$(fr suiseg)"
  rec ctl_light 24
  ev "seg1 click 2nd"; "$M" click $(( SX + SW / 2 )) $(( SY + SH / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "seg1 click 3rd"; "$M" click $(( SX + 5 * SW / 6 )) $(( SY + SH / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "suiseg click 3rd"; "$M" click $(( UX + 5 * UW / 6 )) $(( UY + UH / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "slider click 85"; "$M" click $(( LX + 10 + (LW - 20) * 85 / 100 )) $(( LY + LH / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "slider click 15"; "$M" click $(( LX + 10 + (LW - 20) * 15 / 100 )) $(( LY + LH / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "switch on"; "$M" click $(( WX2 + WW2 / 2 )) $(( WY2 + WH2 / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "switch off"; "$M" click $(( WX2 + WW2 / 2 )) $(( WY2 + WH2 / 2 )) 80 >> "$LOG"; sleep 1.0
  ev "pop open"; "$M" click $(( PX + PW / 2 )) $(( PY + PH / 2 )) 80 >> "$LOG"; sleep 1.3; ev "pop esc"; code 53; sleep 1.2
  ev "pop open2"; "$M" click $(( PX + PW / 2 )) $(( PY + PH / 2 )) 80 >> "$LOG"; sleep 1.0; ev "pop choose"; "$M" click $(( PX + PW / 2 )) $(( PY + PH / 2 + 44 )) 70 >> "$LOG"; sleep 1.4
  recwait
  pkill -f AnimRef
fi
flags; echo "end el $(el)" >> "$LOG"
R="$RUNNER_TEMP/resB"; mkdir -p "$R/res"
( cd "$S" && zip -qr -9 "$R/res/anim2-extra.zip" . -x 'vid/*.mov' )
cp "$S"/vid/*.mov "$R/res/" 2>/dev/null; cp "$LOG" "$S/compile.txt" "$R/res/" 2>/dev/null
ls -la "$R/res" > "$R/res/files.txt"; cat "$R/res/files.txt"
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) anim2 el $(el)" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b anim2-results && git add res && git commit -qm "anim2 $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" anim2-results ) || echo "publish failed"
exit 0
