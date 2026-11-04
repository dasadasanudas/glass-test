#!/bin/bash
# Animation references on macOS 26 with Reduce Transparency, Reduce Motion and Increase Contrast OFF (system UI restarted):
# menu bar menus, context menus, Control Center, Notification Center, Spotlight, Apps, window open/close/minimize, AppKit and
# SwiftUI controls (segmented, sliders, switches, pop-up and pull-down menus) on screen video (screencapture -v), plus AX
# geometry of every open menu, Calendar Day/Week/Month/Year stills (light, dark) and the lock screen.
# Results: branch anim-results (res/*.mov, res/anim-stills.zip, res/log.txt). Event times in log.txt ("ev <unix time> ...").
set +e
START=$(date +%s)
S="$RUNNER_TEMP/anim"; mkdir -p "$S/shots" "$S/vid" "$S/ax"; LOG="$S/log.txt"; : > "$LOG"
el() { echo $(( $(date +%s) - START )); }
ok() { [ "$(el)" -lt "$1" ]; }
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
osa() { T 25 osascript -e "$1" >> "$LOG" 2>&1; }
sw_vers > "$S/os.txt"
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false 2>> "$LOG"; done
python3 drag/wall.py "$S" >> "$LOG" 2>&1
T 15 osascript -e 'tell application "System Events" to get picture of desktop 1' > "$S/defwall.txt" 2>> "$LOG"
clang -O1 -framework ApplicationServices drag/mouse2.c -o "$RUNNER_TEMP/mouse2" > "$S/compile.txt" 2>&1; echo "mouse2 clang exit $?" >> "$S/compile.txt"
M="$RUNNER_TEMP/mouse2"
APP="$RUNNER_TEMP/AnimRef.app"; mkdir -p "$APP/Contents/MacOS"
printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.probe.animref</string><key>CFBundleName</key><string>AnimRef</string><key>CFBundleExecutable</key><string>AnimRef</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>NSPrincipalClass</key><string>NSApplication</string><key>NSHighResolutionCapable</key><true/></dict></plist>' > "$APP/Contents/Info.plist"
( T 300 swiftc -swift-version 5 drag/anim.swift -o "$APP/Contents/MacOS/AnimRef" > "$S/swiftc.txt" 2>&1; echo "swiftc exit $?" >> "$S/swiftc.txt"; codesign --force -s - "$APP" > /dev/null 2>&1 ) &
SWIFT=$!
killall Dock ControlCenter SystemUIServer NotificationCenter Spotlight WindowManager Finder >> "$LOG" 2>&1
sleep 8
ts() { "$M" ts; }
ev() { echo "ev $(ts) $*" >> "$LOG"; }
flags() { T 20 osascript -l JavaScript -e 'ObjC.import("AppKit"); var w = $.NSWorkspace.sharedWorkspace; "RT=" + w.accessibilityDisplayShouldReduceTransparency + " RM=" + w.accessibilityDisplayShouldReduceMotion + " IC=" + w.accessibilityDisplayShouldIncreaseContrast' >> "$LOG" 2>&1; }
dark() { osa "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"; sleep 3; }
wall() { osa "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$S/wall_$1.png\")"; sleep 2.5; }
cmdk() { osa "tell application \"System Events\" to keystroke \"$1\" using command down"; sleep 0.8; }
code() { osa "tell application \"System Events\" to key code $1"; sleep 0.4; }
typ() { osa "tell application \"System Events\" to keystroke \"$1\""; sleep 0.4; }
front() { osa "tell application \"System Events\" to set frontmost of process \"$1\" to true"; sleep 1; }
place() {
  osa "tell application \"System Events\" to tell process \"$1\" to try
  set position of window 1 to {$2, $3}
  set size of window 1 to {$4, $5}
end try"
  sleep 1.2
  echo "$1 bounds $(T 15 osascript -e "tell application \"System Events\" to tell process \"$1\" to get {position, size} of window 1" 2>&1)" >> "$LOG"
}
shot() { screencapture -x "$S/shots/$1.png" 2>> "$LOG"; }
RP=0; REND=0
rec() { ( T $(( $2 + 30 )) screencapture -v -V "$2" -x "$S/vid/$1.mov" >> "$LOG" 2>&1; echo "rec $1 exit $? $(ts)" >> "$LOG" ) & RP=$!; REND=$(( $(date +%s) + $2 )); echo "rec $1 start $(ts) len $2 el $(el)" >> "$LOG"; sleep 2; }
recwait() { while kill -0 $RP 2>/dev/null; do if [ "$(date +%s)" -gt $(( REND + 6 )) ]; then echo "rec overrun $(ts)" >> "$LOG"; pkill -INT -x screencapture; sleep 2; pkill -x screencapture; break; fi; sleep 0.3; done; echo "recwait done el $(el)" >> "$LOG"; }
cat > "$S/mb.js" <<'JS'
function run(argv) {
  const se = Application('System Events'); let s = '';
  for (const pn of argv) {
    let bars = []; try { bars = se.processes.byName(pn).menuBars(); } catch (e) { continue; }
    for (let b = 0; b < bars.length; b++) {
      let items = []; try { items = bars[b].menuBarItems(); } catch (e) {}
      for (const it of items) {
        let n = '', d = '';
        try { n = it.name() || ''; } catch (e) {}
        try { d = it.description() || ''; } catch (e) {}
        try { const q = it.position(), z = it.size(); s += pn + '\t' + b + '\t' + n + '\t' + d + '\t' + q[0] + '\t' + q[1] + '\t' + z[0] + '\t' + z[1] + '\n'; } catch (e) {}
      }
    }
  }
  return s;
}
JS
cat > "$S/mi.js" <<'JS'
function run(argv) {
  const se = Application('System Events'); const p = se.processes.byName(argv[0]);
  const m = p.menuBars[0].menuBarItems.byName(argv[1]).menus[0]; let s = '';
  try { const q = m.position(), z = m.size(); s += '#menu\t' + q[0] + '\t' + q[1] + '\t' + z[0] + '\t' + z[1] + '\n'; } catch (e) {}
  const its = m.menuItems();
  for (const it of its) {
    let n = ''; try { n = it.name() || '-'; } catch (e) { n = '-'; }
    try { const q = it.position(), z = it.size(); s += n + '\t' + q[0] + '\t' + q[1] + '\t' + z[0] + '\t' + z[1] + '\n'; } catch (e) {}
  }
  return s;
}
JS
cat > "$S/dock.js" <<'JS'
function run() {
  const se = Application('System Events'); const d = se.processes.byName('Dock'); let s = '';
  const els = d.lists[0].uiElements();
  for (const e of els) {
    let n = '', sr = ''; try { n = e.name() || ''; } catch (x) {} try { sr = e.subrole() || ''; } catch (x) {}
    try { const q = e.position(), z = e.size(); s += n + '\t' + sr + '\t' + q[0] + '\t' + q[1] + '\t' + z[0] + '\t' + z[1] + '\n'; } catch (x) {}
  }
  return s;
}
JS
cat > "$S/btn.js" <<'JS'
function run(argv) {
  const se = Application('System Events'); const w = se.processes.byName(argv[0]).windows[0]; let s = '';
  const bs = w.buttons();
  for (const b of bs) { let sr = ''; try { sr = b.subrole() || ''; } catch (x) {} try { const q = b.position(), z = b.size(); s += sr + '\t' + q[0] + '\t' + q[1] + '\t' + z[0] + '\t' + z[1] + '\n'; } catch (x) {} }
  try { const q = w.position(), z = w.size(); s += 'window\t' + q[0] + '\t' + q[1] + '\t' + z[0] + '\t' + z[1] + '\n'; } catch (x) {}
  return s;
}
JS
cat > "$S/ax.js" <<'JS'
function run(argv) {
  const se = Application('System Events');
  const p = se.processes.whose({ frontmost: true })[0];
  const out = []; let n = 0;
  function walk(e, d) {
    if (n > 420 || d > 8) return;
    n++; const r = {};
    try { r.role = e.role(); } catch (x) {}
    try { r.name = e.name(); } catch (x) {}
    try { r.desc = e.description(); } catch (x) {}
    try { const v = e.value(); if (typeof v === 'string' || typeof v === 'number') r.value = String(v).slice(0, 40); } catch (x) {}
    try { r.pos = e.position(); r.size = e.size(); } catch (x) {}
    r.depth = d; out.push(r);
    let kids = []; try { kids = e.uiElements(); } catch (x) {}
    for (let i = 0; i < kids.length && i < 50; i++) walk(kids[i], d + 1);
  }
  try { walk(p.windows[0], 0); } catch (x) { out.push({ error: String(x) }); }
  return JSON.stringify(out);
}
JS
MODE=light
mi() { T 12 osascript -l JavaScript "$S/mi.js" "$1" "$2" > "$S/ax/menu_${2}_${MODE}.txt" 2>> "$LOG"; }
mic() { awk -F'\t' -v n="$2" '$1==n {printf "%d %d\n", $2+$4/2, $3+$5/2; exit}' "$S/ax/menu_$1_${MODE}.txt" 2>/dev/null; }
mbc() { awk -F'\t' -v p="$1" -v n="$2" '$1==p && ($3==n || $4==n) {printf "%d %d\n", $5+$7/2, $6+$8/2; exit}' "$S/ax/menubar.txt"; }
dkc() { awk -F'\t' -v n="$1" '($1==n || $2==n) {printf "%d %d\n", $3+$5/2, $4+$6/2; exit}' "$S/ax/$2"; }
flags
wall bands; dark false
osa 'tell application "Finder" to close every window'
osa 'tell application "Finder" to activate'
osa 'tell application "Finder" to make new Finder window to (path to home folder)'
sleep 2; place Finder 60 60 964 644; front Finder
T 30 osascript -l JavaScript "$S/mb.js" Finder ControlCenter Spotlight SystemUIServer > "$S/ax/menubar.txt" 2>> "$LOG"
T 20 osascript -l JavaScript "$S/dock.js" > "$S/ax/dock.txt" 2>> "$LOG"
read AX AY <<< "$(mbc Finder Apple)"; : ${AX:=18} ${AY:=12}
read FX FY <<< "$(mbc Finder File)"; : ${FX:=104} ${FY:=12}
read EX EY <<< "$(mbc Finder Edit)"; : ${EX:=142} ${EY:=12}
read VX VY <<< "$(mbc Finder View)"; : ${VX:=182} ${VY:=12}
read GX GY <<< "$(mbc Finder Go)"; : ${GX:=218} ${GY:=12}
read WX WY <<< "$(mbc Finder Window)"; : ${WX:=262} ${WY:=12}
read CCX CCY <<< "$(mbc ControlCenter 'Control Center')"; : ${CCX:=930} ${CCY:=12}
read CLX CLY <<< "$(mbc ControlCenter 'Clock')"; : ${CLX:=985} ${CLY:=12}
read DFX DFY <<< "$(dkc Finder dock.txt)"; read APX APY <<< "$(dkc Apps dock.txt)"
echo "pos apple $AX file $FX edit $EX view $VX go $GX win $WX cc $CCX,$CCY clock $CLX,$CLY dockfinder $DFX,$DFY apps $APX,$APY" >> "$LOG"
"$M" move 520 520 >> "$LOG"
# ---------------- 1. menu bar, light
rec menubar_light 62
ev "click File"; "$M" click $FX $FY 90 >> "$LOG"; sleep 1.0; shot mb_file_light; mi Finder File
ev "glide File to Edit"; "$M" glide $FX $FY $EX $EY 260 >> "$LOG"; sleep 0.8; mi Finder Edit
ev "glide Edit to View"; "$M" glide $EX $EY $VX $VY 260 >> "$LOG"; sleep 0.8; shot mb_view_light; mi Finder View
ev "glide View to Go"; "$M" glide $VX $VY $GX $GY 260 >> "$LOG"; sleep 0.8; mi Finder Go
ev "glide Go to Window"; "$M" glide $GX $GY $WX $WY 260 >> "$LOG"; sleep 0.8; mi Finder Window
ev "hover down Window"; "$M" glide $WX $WY $WX $(( WY + 50 )) 350 >> "$LOG"; sleep 0.5; "$M" glide $WX $(( WY + 50 )) $WX $(( WY + 100 )) 350 >> "$LOG"; sleep 0.6
ev "escape"; code 53; sleep 1.2
ev "click View"; "$M" click $VX $VY 90 >> "$LOG"; sleep 0.9
read IX IY <<< "$(mic View 'as List')"; : ${IX:=$(( VX + 40 ))} ${IY:=$(( VY + 52 ))}
ev "hover as List"; "$M" glide $VX $VY $IX $IY 400 >> "$LOG"; sleep 0.6; shot mb_view_hover_light
ev "choose as List"; "$M" click $IX $IY 70 >> "$LOG"; sleep 1.6
ev "click Go then outside"; "$M" click $GX $GY 90 >> "$LOG"; sleep 1.0; "$M" click 30 430 60 >> "$LOG"; sleep 1.3
read JX JY <<< "$(mic Edit 'Select All')"; : ${JX:=$(( EX + 40 ))} ${JY:=$(( EY + 150 ))}
ev "press-drag-release Edit to Select All"; "$M" move $EX $EY; "$M" down $EX $EY >> "$LOG"; sleep 0.7; "$M" glide $EX $EY $JX $JY 500 d >> "$LOG"; sleep 0.4; "$M" up $JX $JY >> "$LOG"; sleep 1.5
ev "Apple menu"; "$M" click $AX $AY 90 >> "$LOG"; sleep 1.0; shot mb_apple_light; mi Finder Apple; code 53; sleep 1.0
ev "fast sweep"; "$M" click $FX $FY 90 >> "$LOG"; sleep 0.5; "$M" glide $FX $FY $WX $WY 300 >> "$LOG"; sleep 0.6; "$M" glide $WX $WY $FX $FY 300 >> "$LOG"; sleep 0.6; code 53; sleep 1.0
ev "right-click desktop"; "$M" rclick 30 430 >> "$LOG"; sleep 1.0; shot ctx_desktop_light; code 53; sleep 1.0
recwait
front Finder; cmdk 1
# ---------------- 2. controls, light (AppKit + SwiftUI)
wait $SWIFT; cat "$S/swiftc.txt" >> "$S/compile.txt"; echo "swift done el $(el)" >> "$LOG"
HAVEAPP=0; [ -x "$APP/Contents/MacOS/AnimRef" ] && HAVEAPP=1
fr() { awk -v n="$1" '$1==n {print $2, $3, $4, $5; exit}' "$S/frames.txt"; }
segs() { local n=$1 x=$2 y=$3 w=$4 h=$5; [ -z "$h" ] && return; local cy=$(( y + h / 2 )) a=$(( x + w / 6 )) b=$(( x + w / 2 )) c=$(( x + 5 * w / 6 ))
  ev "$n click 3rd"; "$M" click $c $cy 350 >> "$LOG"; sleep 0.9
  ev "$n press selected"; "$M" move $c $cy; "$M" down $c $cy >> "$LOG"; sleep 0.6; shot "${n}_${MODE}_hold"
  ev "$n drag to 1st"; "$M" glide $c $cy $a $cy 900 d >> "$LOG"; sleep 0.3; shot "${n}_${MODE}_drag"; "$M" up $a $cy >> "$LOG"; sleep 0.9
  ev "$n quick 2nd"; "$M" click $b $cy 70 >> "$LOG"; sleep 0.9; }
slid() { local n=$1 x=$2 y=$3 w=$4 h=$5 cy=$6; [ -z "$h" ] && return; [ -z "$cy" ] && cy=$(( y + h / 2 ))
  local p8=$(( x + 10 + (w - 20) * 8 / 10 )) p2=$(( x + 10 + (w - 20) * 2 / 10 )) p6=$(( x + 10 + (w - 20) * 6 / 10 ))
  ev "$n click track 80"; "$M" click $p8 $cy 400 >> "$LOG"; sleep 1.0
  ev "$n press knob"; "$M" move $p8 $cy; "$M" down $p8 $cy >> "$LOG"; sleep 0.6; shot "${n}_${MODE}_hold"
  ev "$n drag to 20"; "$M" glide $p8 $cy $p2 $cy 900 d >> "$LOG"; sleep 0.3; "$M" up $p2 $cy >> "$LOG"; sleep 1.0
  ev "$n quick 60"; "$M" click $p6 $cy 70 >> "$LOG"; sleep 1.0; }
swit() { local n=$1 x=$2 y=$3 w=$4 h=$5; [ -z "$h" ] && return; local cx=$(( x + w / 2 )) cy=$(( y + h / 2 ))
  ev "$n click"; "$M" click $cx $cy 90 >> "$LOG"; sleep 1.0
  ev "$n press hold"; "$M" move $cx $cy; "$M" down $cx $cy >> "$LOG"; sleep 0.7; shot "${n}_${MODE}_hold"; "$M" up $cx $cy >> "$LOG"; sleep 1.0
  ev "$n drag"; "$M" move $(( x + 7 )) $cy; "$M" down $(( x + 7 )) $cy >> "$LOG"; sleep 0.25; "$M" glide $(( x + 7 )) $cy $(( x + w - 7 )) $cy 500 d >> "$LOG"; sleep 0.3; "$M" up $(( x + w - 7 )) $cy >> "$LOG"; sleep 1.0; }
popm() { local n=$1 x=$2 y=$3 w=$4 h=$5; [ -z "$h" ] && return; local cx=$(( x + w / 2 )) cy=$(( y + h / 2 ))
  ev "$n open"; "$M" click $cx $cy 90 >> "$LOG"; sleep 1.0; shot "${n}_${MODE}_open"
  ev "$n hover"; "$M" glide $cx $cy $cx $(( cy + 66 )) 450 >> "$LOG"; sleep 0.6; shot "${n}_${MODE}_hover"
  ev "$n choose"; "$M" click $cx $(( cy + 66 )) 70 >> "$LOG"; sleep 1.2
  ev "$n reopen"; "$M" click $cx $cy 90 >> "$LOG"; sleep 1.0; shot "${n}_${MODE}_open2"
  ev "$n esc"; code 53; sleep 0.9; }
pulld() { local n=$1 x=$2 y=$3 w=$4 h=$5; [ -z "$h" ] && return; local cx=$(( x + w / 2 )) cy=$(( y + h / 2 ))
  ev "$n open"; "$M" click $cx $cy 90 >> "$LOG"; sleep 1.0; shot "${n}_${MODE}_open"
  ev "$n esc"; code 53; sleep 0.9; }
if [ $HAVEAPP = 1 ]; then
  open -n --stdout "$S/app_out.txt" --stderr "$S/app_err.txt" "$APP" --args "$S"
  for i in $(seq 1 40); do [ -f "$S/frames.txt" ] && break; sleep 0.5; done
  front AnimRef; sleep 5; cat "$S/frames.txt" >> "$LOG"
  shot ctl_static_light
  read K1X K1Y K1W K1H <<< "$(fr knob1)"; read K2X K2Y K2W K2H <<< "$(fr knob2)"
  C1=""; C2=""; [ -n "$K1H" ] && C1=$(( K1Y + K1H / 2 )); [ -n "$K2H" ] && C2=$(( K2Y + K2H / 2 ))
  rec ctl_light 84
  segs seg1 $(fr seg1); segs seg2 $(fr seg2); segs suiseg $(fr suiseg); segs tbseg $(fr tbseg)
  slid slider1 $(fr slider1) $C1; slid slider2 $(fr slider2) $C2; slid suislider $(fr suislider)
  swit switch1 $(fr switch1); swit suitoggle $(fr suitoggle)
  popm pop1 $(fr pop1); pulld pull1 $(fr pull1); popm suimenu $(fr suimenu)
  recwait
fi
# ---------------- 3. Calendar views (stills, light and dark) + AX of the week view
if ok 430; then
  open -a Calendar >> "$LOG" 2>&1; sleep 6; front Calendar; code 36; sleep 1; front Calendar
  place Calendar 60 60 964 649
  rec cal_light 17
  for v in 1 2 3 4; do ev "cal view $v"; cmdk $v; sleep 1.5; shot "cal_v${v}_bands_light"; done
  recwait
  cmdk 2; sleep 1; T 28 osascript -l JavaScript "$S/ax.js" > "$S/ax/cal_week_light.json" 2>> "$LOG"
  dark true
  for v in 1 2 3 4; do cmdk $v; sleep 1.3; shot "cal_v${v}_bands_dark"; done
  dark false
  killall Calendar >> "$LOG" 2>&1; sleep 1
fi
# ---------------- 4. system UI: Control Center, Notification Center, Spotlight, Apps, Dock menu
if ok 500; then
  front Finder
  rec sys_light 40
  ev "CC open"; "$M" click $CCX $CCY 90 >> "$LOG"; sleep 1.6; shot cc_open_light
  ev "CC close"; "$M" click $CCX $CCY 90 >> "$LOG"; sleep 1.3
  ev "NC open"; "$M" click $CLX $CLY 90 >> "$LOG"; sleep 1.6; shot nc_open_light
  ev "NC close"; "$M" click $CLX $CLY 90 >> "$LOG"; sleep 1.3
  ev "Spotlight open"; osa 'tell application "System Events" to keystroke space using command down'; sleep 1.4; typ cal; sleep 1.2; shot spot_typed_light
  ev "Spotlight close"; code 53; sleep 0.5; code 53; sleep 1.2
  if [ -n "$APX" ]; then ev "Apps open"; "$M" click $APX $APY 90 >> "$LOG"; sleep 2.0; shot apps_open_light; ev "Apps close"; code 53; sleep 1.5; fi
  if [ -n "$DFX" ]; then ev "Dock menu"; "$M" rclick $DFX $DFY >> "$LOG"; sleep 1.0; shot dock_menu_light; code 53; sleep 1.0; fi
  recwait
fi
# ---------------- 5. windows: open, close, minimize, restore, red close
if ok 545; then
  front Finder
  rec win_light 25
  ev "new window"; cmdk n; sleep 1.5
  ev "close window cmd-w"; cmdk w; sleep 1.4
  T 15 osascript -l JavaScript "$S/btn.js" Finder > "$S/ax/btn.txt" 2>> "$LOG"
  read MX MY <<< "$(awk -F'\t' '$1=="AXMinimizeButton"{printf "%d %d\n",$2+$4/2,$3+$5/2; exit}' "$S/ax/btn.txt")"
  read QX QY <<< "$(awk -F'\t' '$1=="AXCloseButton"{printf "%d %d\n",$2+$4/2,$3+$5/2; exit}' "$S/ax/btn.txt")"
  if [ -n "$MX" ]; then
    ev "minimize"; "$M" click $MX $MY 90 >> "$LOG"; sleep 2.2; shot win_min_light
    T 15 osascript -l JavaScript "$S/dock.js" > "$S/ax/dock2.txt" 2>> "$LOG"
    read RX RY <<< "$(dkc AXMinimizedWindowDockItem dock2.txt)"
    [ -n "$RX" ] && { ev "restore"; "$M" click $RX $RY 90 >> "$LOG"; sleep 2.2; }
  fi
  [ -n "$QX" ] && { ev "close red"; "$M" click $QX $QY 90 >> "$LOG"; sleep 1.5; }
  recwait
fi
# ---------------- 6. controls, dark
if ok 600 && [ $HAVEAPP = 1 ]; then
  MODE=dark; dark true; front AnimRef; sleep 1; shot ctl_static_dark
  rec ctl_dark 40
  segs seg1 $(fr seg1); segs suiseg $(fr suiseg)
  slid slider1 $(fr slider1) $C1; swit switch1 $(fr switch1); popm pop1 $(fr pop1)
  recwait
fi
# ---------------- 7. menu bar, dark
if ok 650; then
  MODE=dark; [ "$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')" = true ] || dark true
  front Finder
  rec menubar_dark 18
  ev "dark click File"; "$M" click $FX $FY 90 >> "$LOG"; sleep 1.0; shot mb_file_dark
  ev "dark glide to View"; "$M" glide $FX $FY $VX $VY 400 >> "$LOG"; sleep 0.9; shot mb_view_dark
  ev "dark escape"; code 53; sleep 1.0
  ev "dark Apple"; "$M" click $AX $AY 90 >> "$LOG"; sleep 1.0; shot mb_apple_dark; code 53; sleep 1.0
  ev "dark right-click desktop"; "$M" rclick 30 430 >> "$LOG"; sleep 1.0; shot ctx_desktop_dark; code 53; sleep 0.8
  recwait
fi
MODE=light; dark false
pkill -f AnimRef
# ---------------- 8. lock screen (default wallpaper)
if ok 690; then
  DW=$(tr -d '\n' < "$S/defwall.txt"); [ -n "$DW" ] && osa "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$DW\")"
  sleep 2; shot desk_default_light
  rec lock 12
  ev "lock"; osa 'tell application "System Events" to keystroke "q" using {control down, command down}'
  sleep 3; shot lock_a; sleep 2.5; shot lock_b; "$M" move 512 600 >> "$LOG"; sleep 1.5; shot lock_c
  recwait
fi
flags
echo "end el $(el)" >> "$LOG"
R="$RUNNER_TEMP/resA"; mkdir -p "$R/res"
( cd "$S" && zip -qr -9 "$R/res/anim-stills.zip" . -x 'vid/*' )
cp "$S"/vid/*.mov "$R/res/" 2>/dev/null
cp "$LOG" "$S/compile.txt" "$R/res/" 2>/dev/null
ls -la "$R/res" > "$R/res/files.txt"; cat "$R/res/files.txt"; tail -n 30 "$LOG"
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) anim el $(el)" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b anim-results && git add res && git commit -qm "anim $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" anim-results ) || echo "publish failed"
exit 0
