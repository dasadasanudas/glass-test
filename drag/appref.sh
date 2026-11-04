#!/bin/bash
# App window references with Reduce Transparency, Reduce Motion and Increase Contrast OFF for every process. The runner image
# ships RT and RM on and running processes keep what they read at launch, so: write the prefs, restart the system UI and Finder,
# then launch every app fresh. Each app sits at the bounds MacWeb's same-scene test uses, over the bands and tiles wallpapers
# (drag/wall.py), light and dark, plus inactive shots and AX trees (role, name, frame) for Finder's views and a few apps.
set +e
S="$RUNNER_TEMP/app"; mkdir -p "$S/shots" "$S/ax"; LOG="$S/log.txt"
sw_vers > "$S/os.txt"
for k in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do defaults write com.apple.universalaccess $k -bool false 2>> "$LOG"; done
python3 drag/wall.py "$S" >> "$LOG" 2>&1
cat > "$S/ax.js" <<'AX_EOF'
function run(argv) {
  const se = Application('System Events');
  const p = se.processes.whose({ frontmost: true })[0];
  const out = []; let n = 0;
  function walk(e, d) {
    if (n > 700 || d > 9) return;
    n++; const r = {};
    try { r.role = e.role(); } catch (x) {}
    try { r.sub = e.subrole(); } catch (x) {}
    try { r.name = e.name(); } catch (x) {}
    try { r.desc = e.description(); } catch (x) {}
    try { const v = e.value(); if (typeof v === 'string' || typeof v === 'number') r.value = String(v).slice(0, 60); } catch (x) {}
    try { r.pos = e.position(); r.size = e.size(); } catch (x) {}
    r.depth = d; out.push(r);
    let kids = []; try { kids = e.uiElements(); } catch (x) {}
    for (let i = 0; i < kids.length && i < 60; i++) walk(kids[i], d + 1);
  }
  try { walk(p.windows[0], 0); } catch (x) { out.push({ error: String(x) }); }
  return JSON.stringify(out);
}
AX_EOF
killall Dock ControlCenter SystemUIServer NotificationCenter Spotlight WindowManager Finder >> "$LOG" 2>&1
sleep 8
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
osa() { T 25 osascript -e "$1" >> "$LOG" 2>&1; }
flags() { T 20 osascript -l JavaScript -e 'ObjC.import("AppKit"); var w = $.NSWorkspace.sharedWorkspace; "RT=" + w.accessibilityDisplayShouldReduceTransparency + " RM=" + w.accessibilityDisplayShouldReduceMotion + " IC=" + w.accessibilityDisplayShouldIncreaseContrast' >> "$LOG" 2>&1; }
dark() { osa "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"; sleep 3; }
wall() { osa "tell application \"System Events\" to tell every desktop to set picture to (POSIX file \"$S/wall_$1.png\")"; sleep 2.5; }
cmdk() { osa "tell application \"System Events\" to keystroke \"$1\" using command down"; sleep 0.8; }
code() { osa "tell application \"System Events\" to key code $1"; sleep 0.8; }
typ() { osa "tell application \"System Events\" to keystroke \"$1\""; sleep 0.4; }
front() { osa "tell application \"System Events\" to set frontmost of process \"$1\" to true"; sleep 1; }
place() {
  osa "tell application \"System Events\" to tell process \"$1\" to try
  set position of window 1 to {$2, $3}
  set size of window 1 to {$4, $5}
end try"
  sleep 1.5
  echo "$1 bounds $(T 15 osascript -e "tell application \"System Events\" to tell process \"$1\" to get {position, size} of window 1" 2>&1)" >> "$LOG"
}
shot() { screencapture -x "$S/shots/$1.png" 2>> "$LOG"; }
ax() { T 50 osascript -l JavaScript "$S/ax.js" > "$S/ax/$1.json" 2>> "$LOG"; echo "ax $1 $?" >> "$LOG"; }
# four looks for the app in front: light bands, light tiles, dark tiles, dark bands (inactive copies in bands when $3 = in)
looks() {
  local t="$1" p="$2"
  wall bands; dark false; front "$p"; shot "${t}_bands_light"
  if [ "$3" = in ]; then front Finder; shot "${t}_bands_light_inactive"; front "$p"; fi
  wall tiles; shot "${t}_tiles_light"
  dark true; shot "${t}_tiles_dark"
  wall bands; shot "${t}_bands_dark"
  if [ "$3" = in ]; then front Finder; shot "${t}_bands_dark_inactive"; front "$p"; fi
  echo "looks $t done $(date +%T)" >> "$LOG"
}
flags
wall bands; dark false
# ---- Finder: home folder in icon, list and column view, plus a selected item
osa 'tell application "Finder" to close every window'
osa 'tell application "Finder" to activate'
osa 'tell application "Finder" to make new Finder window to (path to home folder)'
sleep 2; place Finder 60 60 964 644
front Finder; cmdk 1; sleep 1; ax finder_icon_light
looks finder_icon Finder
code 124; sleep 0.8; shot finder_icon_sel_bands_dark; dark false; shot finder_icon_sel_bands_light
front Finder; cmdk 2; sleep 1.5; ax finder_list_light
looks finder_list Finder
front Finder; cmdk 3; sleep 1.5; ax finder_column_light
looks finder_column Finder
front Finder; cmdk 1; sleep 1
osa 'tell application "Finder" to close every window'
# ---- other apps, launched fresh
app() {   # name tag x y w h [in] [axname]
  local n="$1" t="$2"
  dark false; wall bands
  open -a "$n" >> "$LOG" 2>&1; sleep 6
  front "$n"
  case "$t" in
    settings) open "x-apple.systempreferences:com.apple.Appearance-Settings.extension" >> "$LOG" 2>&1; sleep 3 ;;
    notes) code 36; sleep 1.5; cmdk n; sleep 1; typ "Weekend plans"; code 36; typ "Pick up the film camera, call Maya, finish the Blender scene."; sleep 1 ;;
    textedit) code 53; sleep 1; cmdk n; sleep 1.5; typ "The quick brown fox jumps over the lazy dog. Liquid Glass 0123456789"; sleep 1 ;;
    reminders) code 36; sleep 1.5 ;;
    calendar) code 36; sleep 1.5 ;;
  esac
  front "$n"; place "$n" "$3" "$4" "$5" "$6"
  [ -n "$8" ] && ax "$8"
  looks "$t" "$n" "$7"
  killall "$n" >> "$LOG" 2>&1; sleep 1.5
}
app "System Settings" settings 60 60 723 647 in settings_light
app Notes notes 60 60 1000 660 in notes_light
app Calculator calculator 60 60 230 408 in
app TextEdit textedit 60 60 964 649 in
app Terminal terminal 60 60 961 649 in
app Safari safari 60 60 1000 680 in safari_light
app Reminders reminders 60 30 964 692 in reminders_light
app Calendar calendar 60 60 964 649 in
app Clock clock 60 60 1000 681 in
dark false
flags
( cd "$S" && zip -qr -9 "$RUNNER_TEMP/appref.zip" . )
ls -la "$RUNNER_TEMP/appref.zip"; ls "$S/shots" | wc -l; tail -n 40 "$LOG"
R="$RUNNER_TEMP/res0"; mkdir -p "$R/res"; cp "$RUNNER_TEMP/appref.zip" "$LOG" "$R/res/" 2>/dev/null
echo "$GITHUB_RUN_ID $(git rev-parse HEAD) appref" > "$R/res/run_id.txt"
gh auth setup-git >/dev/null 2>&1 || true
( cd "$R" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b drag-results && git add res && git commit -qm "appref $GITHUB_RUN_ID" && git push -q -f "https://github.com/${REPO}.git" drag-results ) || echo "publish failed"
exit 0
