#!/bin/bash
# Live Mac: shares this runner's screen as a web page (noVNC) through a public HTTPS link (Cloudflare quick
# tunnel). Progress and the link go to s/status.txt on the live-status branch and the job log. Stop it by
# cancelling the run.
# Login: the page asks for a Password only: type the first 8 characters of LIVE_MAC_PASSWORD.
# Nov 4 findings: Apple Screen Sharing (port 5900) accepts the screen password but shows a separate login
# window (user "Anka"), not runner's desktop. macVNC (LibVNC's macOS server, built here, port 5901) shows the
# real desktop, so the page uses 5901 whenever the on-Mac self-test (live/vnc_selftest.py) logs in there.
# Nov 5: GitHub's image ships a solid black wallpaper and turns Reduce Transparency + Reduce Motion ON
# (actions/runner-images configure-system.sh), which kills Liquid Glass (and the knob lens on switches and
# sliders, which only shows with Reduce Motion off). Both are undone at start. live/probe.sh logs display
# modes, accounts, authorization rights and the frame-rate ceiling to s/probe.txt, and raises the resolution.
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
MIN="${MINUTES:-}"; [ -z "$MIN" ] && MIN=$(cat live/minutes.txt 2>/dev/null || echo 60)
MIN=$(( MIN > 340 ? 340 : MIN ))
if [ -n "$LIVE_PASSWORD" ]; then PW="$LIVE_PASSWORD"; NOTE="password: your LIVE_MAC_PASSWORD secret"
else PW=$(openssl rand -hex 4); NOTE="no LIVE_MAC_PASSWORD secret set: a random password was used (only the test key can read it)"; fi
echo "::add-mask::$PW"
ME=$(whoami); A=livemac
START=$(date -u '+%Y-%m-%d %H:%M'); END=$(date -u -v+${MIN}M '+%Y-%m-%d %H:%M' 2>/dev/null)
URL=""; VNC="?"; WEB="?"; CODES=""; CONSOLE="?"; SHOT="none"; TOK="?"; VPW="?"; SECT="?"; PATCH="?"; VTEST="?"; VTEST2="not run"; TCCR="?"; MVB="?"; PORT=5900; WALLR="?"; WALLS="?"; ACC="?"; SHIPPED="?"; RES="?"; AUTHR="?"
publish() {
  D=$(mktemp -d); mkdir -p "$D/s"
  {
    echo "state: $1"
    echo "link: ${URL:-none}/vnc.html?autoconnect=1&resize=scale"
    echo "login: Password only -> first 8 characters of your secret"
    echo "page uses port: $PORT (5900 = Apple Screen Sharing, 5901 = macVNC)"
    echo "accessibility flags as the image ships them (RT/RM/IC): $SHIPPED"
    echo "glass settings now (Reduce Transparency / Reduce Motion / Increase Contrast): $ACC"
    echo "screen resolution: $RES"
    echo "admin prompts suppressed: $AUTHR"
    echo "wallpaper: $WALLR"
    echo "wallpapers on this image: $WALLS"
    echo "self-test 5900 Apple Screen Sharing (real login on the Mac): $VTEST"
    echo "self-test 5901 macVNC (real login on the Mac): $VTEST2"
    echo "macVNC build: $MVB"
    echo "permissions (TCC): $TCCR"
    echo "auth types 5900 offers (2 = screen password, 30 = Apple username login): $SECT"
    echo "noVNC prefers screen password: $PATCH"
    echo "secure token $ME: $TOK"
    echo "screen (VNC) password file: $VPW"
    echo "screen sharing: $VNC"
    echo "web page (local check): $WEB"
    echo "console user: $CONSOLE"
    echo "local screenshot: $SHOT (s/screen.png)"
    echo "machine specs: $(sysctl -n hw.ncpu) cores, $(( $(sysctl -n hw.memsize) / 1073741824 )) GB RAM, $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo "step exit codes: $CODES"
    echo "minutes: $MIN"
    echo "started (UTC): $START"
    echo "ends about (UTC): $END"
    echo "run: ${GITHUB_RUN_ID:-?}"
    echo "machine: $(uname -m) $(sw_vers -productVersion 2>/dev/null)"
    echo "$NOTE"
    if [ -z "$LIVE_PASSWORD" ] && [ -f live/test_pub.pem ]; then echo "test: $(printf %s "$PW" | openssl pkeyutl -encrypt -pubin -inkey live/test_pub.pem 2>/dev/null | base64 | tr -d '\n')"; fi
  } > "$D/s/status.txt"
  for f in screen vnc vnc5901 vnc5901_menu; do [ -f /tmp/$f.png ] && cp /tmp/$f.png "$D/s/$f.png"; done
  [ -f /tmp/mvbuild_tail.txt ] && cp /tmp/mvbuild_tail.txt "$D/s/macvnc_build.txt"
  [ -f /tmp/probe.txt ] && cp /tmp/probe.txt "$D/s/probe.txt"
  ( cd "$D" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b live-status && git add s && git commit -qm "live mac $1" && T 60 git -c credential.helper= -c core.askPass= push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" live-status ) > /dev/null 2>&1 || echo "publish failed ($1)"
}
publish starting
# build macVNC in the background while the rest is set up
( export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  { T 420 brew install libvncserver; which cmake >/dev/null || T 300 brew install cmake; } > /tmp/brew.txt 2>&1
  T 120 git clone -q --depth 1 https://github.com/LibVNC/macVNC.git /tmp/macvnc > /tmp/mvclone.txt 2>&1
  cd /tmp/macvnc && T 200 cmake -B build -DCMAKE_BUILD_TYPE=Release . > /tmp/mvcmake.txt 2>&1 && T 400 cmake --build build -j 4 > /tmp/mvbuild.txt 2>&1
  echo $? > /tmp/mv_done ) &
# what the image ships (proof for the no-glass and no-knob-lens question)
SHIPPED="$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo unset) / $(defaults read com.apple.universalaccess reduceMotion 2>/dev/null || echo unset) / $(defaults read com.apple.universalaccess increaseContrast 2>/dev/null || echo unset)"
# Liquid Glass back on: undo them and restart the system UI so Dock, menu bar, Control Center and Finder pick
# it up (same method as drag/sysref.sh). Reduce Motion matters too: it removes the glass lens on switch and
# slider knobs while dragging.
for K2 in reduceTransparency reduceMotion increaseContrast differentiateWithoutColor; do
  T 15 defaults write com.apple.universalaccess $K2 -bool false > /dev/null 2>&1
done
T 15 defaults write com.apple.Accessibility ReduceMotionEnabled -int 0 > /dev/null 2>&1
T 15 killall Dock ControlCenter SystemUIServer NotificationCenter Spotlight WindowManager Finder > /dev/null 2>&1
sleep 8
ACC="$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo ?) / $(defaults read com.apple.universalaccess reduceMotion 2>/dev/null || echo ?) / $(defaults read com.apple.universalaccess increaseContrast 2>/dev/null || echo ?) (0 = off = glass on)"
# admin rights without password prompts: the GUI asks for an account whose password we do not own, so allow
# the rights outright and make sure the console user is an admin
T 20 sudo dseditgroup -o edit -a "$ME" -t user admin > /dev/null 2>&1
AOK=0
for R in system.preferences system.preferences.accessibility system.preferences.datetime system.preferences.desktop system.preferences.dock system.preferences.energysaver system.preferences.network system.preferences.printing system.preferences.security system.preferences.sharing system.preferences.softwareupdate; do
  T 15 sudo security authorizationdb write $R allow > /dev/null 2>&1 && AOK=$((AOK+1))
done
AUTHR="$AOK of 11 preference rights set to allow; $ME added to admin"
# a real wallpaper (GitHub's image uses Solid Colors/Black.png): prefer Tahoe, then any macOS picture, then a non-black solid colour
DP="/System/Library/Desktop Pictures"
WALLS=$(ls "$DP" 2>/dev/null | head -12 | tr '\n' ',' | sed 's/,$//')
WALL=$(ls "$DP"/*.heic 2>/dev/null | grep -i tahoe | head -1)
[ -z "$WALL" ] && WALL=$(ls "$DP"/*.heic "$DP"/*.jpg "$DP"/*.png 2>/dev/null | head -1)
[ -z "$WALL" ] && WALL=$(ls "$DP/Solid Colors/"*.png 2>/dev/null | grep -vi black | head -1)
if [ -n "$WALL" ]; then
  T 30 osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$WALL\"" > /tmp/wall.txt 2>&1 && WALLR="$WALL" || WALLR="failed: $(head -c 100 /tmp/wall.txt | tr '\n' ' ')"
else WALLR="none found"; fi
# diagnostics + resolution raise
T 300 bash live/probe.sh > /dev/null 2>&1
RES=$(grep '^RES=' /tmp/probe.txt 2>/dev/null | tail -1 | sed 's/^RES=//')
publish "probe done"
# keep the console display awake for the whole session
T 20 sudo pmset -a displaysleep 0 sleep 0 disksleep 0 > /tmp/pm.txt 2>&1; CODES="$CODES $?"
nohup caffeinate -dimsu -t $(( MIN * 60 + 900 )) > /dev/null 2>&1 &
T 10 caffeinate -u -t 3 > /dev/null 2>&1
T 20 defaults -currentHost write com.apple.screensaver idleTime -int 0 > /tmp/ss1.txt 2>&1; CODES="$CODES $?"
T 20 sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime -int 0 > /tmp/ss2.txt 2>&1; CODES="$CODES $?"
T 20 sudo defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 0 > /tmp/ss3.txt 2>&1; CODES="$CODES $?"
TOK=$(T 20 sudo sysadminctl -secureTokenStatus "$ME" 2>&1 | grep -Eo 'ENABLED|DISABLED' | head -1)
T 90 sudo sysadminctl -addUser "$A" -fullName "Live Mac" -password "$PW" -admin > /tmp/acct1.txt 2>&1; CODES="$CODES $?"
# permissions (TCC): Screen Recording + input (SIP is off on these runners)
SIP=$(csrutil status 2>/dev/null | head -1 | sed 's/.*: //')
DB="/Library/Application Support/com.apple.TCC/TCC.db"
TCCN=0; TCCE=""
addtcc() { sudo sqlite3 -cmd ".timeout 8000" "$DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags, last_modified) VALUES ('$1', '$2', $3, 2, 4, 1, 'UNUSED', 0, $(date +%s));" > /tmp/tcc_err.txt 2>&1 && TCCN=$((TCCN+1)) || TCCE="$(head -c 90 /tmp/tcc_err.txt | tr '\n' ' ')"; }
SVCS="kTCCServiceScreenCapture kTCCServicePostEvent kTCCServiceAccessibility kTCCServiceListenEvent"
RM=/System/Library/CoreServices/RemoteManagement
for SV in $SVCS; do
  for B in "$RM"/*.bundle "$RM"/*.app; do
    [ -d "$B" ] || continue
    ID=$(defaults read "$B/Contents/Info" CFBundleIdentifier 2>/dev/null); [ -n "$ID" ] && addtcc "$SV" "$ID" 0
    for X in "$B"/Contents/MacOS/*; do [ -f "$X" ] && addtcc "$SV" "$X" 1; done
  done
done
sudo killall tccd > /dev/null 2>&1
TCCR="SIP $SIP; rows added $TCCN${TCCE:+; error: $TCCE}"
# Apple Screen Sharing on 5900 with the screen password (kept as a fallback)
T 20 sudo dseditgroup -o create -q com.apple.access_screensharing > /tmp/grp0.txt 2>&1; CODES="$CODES $?"
T 20 sudo dseditgroup -o edit -a "$ME" -t user com.apple.access_screensharing > /tmp/grp1.txt 2>&1; CODES="$CODES $?"
T 20 sudo dseditgroup -o edit -a "$A" -t user com.apple.access_screensharing > /tmp/grp2.txt 2>&1; CODES="$CODES $?"
K=$RM/ARDAgent.app/Contents/Resources/kickstart
T 60 sudo "$K" -configure -allowAccessFor -allUsers -privs -all > /tmp/share0.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -configure -access -on -users "$ME,$A" -privs -all > /tmp/share1.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw "${PW:0:8}" > /tmp/share2.txt 2>&1; CODES="$CODES $?"
printf %s "${PW:0:8}" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA" } $_ = <STDIN>; $_ = "" unless defined; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) } print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null 2>/tmp/vpw.txt; R=$?; CODES="$CODES $R"
T 10 sudo chmod 600 /Library/Preferences/com.apple.VNCSettings.txt > /dev/null 2>&1
[ "$R" = "0" ] && VPW="written ($(sudo wc -c /Library/Preferences/com.apple.VNCSettings.txt 2>/dev/null | awk '{print $1}') bytes)" || VPW="failed"
T 20 sudo defaults write /Library/Preferences/com.apple.RemoteManagement VNCLegacyConnectionsEnabled -bool true > /tmp/share2b.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -restart -agent -console > /tmp/share3.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -activate > /tmp/share4.txt 2>&1; CODES="$CODES $?"
sudo killall screensharingd ScreensharingAgent > /dev/null 2>&1
T 20 sudo launchctl enable system/com.apple.screensharing > /tmp/share5.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist > /tmp/share6.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl kickstart -k system/com.apple.screensharing > /tmp/share7.txt 2>&1; CODES="$CODES $?"
sleep 3
VNC=$(T 5 nc -z localhost 5900 >/dev/null 2>&1 && echo up || echo down)
SECT=$(T 10 python3 -c "import socket; s=socket.create_connection(('127.0.0.1',5900),5); v=s.recv(12); s.sendall(b'RFB 003.008\n'); n=s.recv(1)[0]; print(v.decode().strip(), list(s.recv(n)))" 2>&1 | tail -1)
CONSOLE=$(stat -f %Su /dev/console 2>/dev/null)
T 10 caffeinate -u -t 2 > /dev/null 2>&1
sleep 2
VTEST=$(T 45 python3 live/vnc_selftest.py "${PW:0:8}" 5900 /tmp/vnc.png 2>&1 | tail -1)
T 20 screencapture -x /tmp/screen.png > /tmp/shot.txt 2>&1 && SHOT="taken $(stat -f %z /tmp/screen.png 2>/dev/null) bytes" || SHOT="failed"
publish "screen sharing step done"
# macVNC on 5901 (wait for the background build, max ~9 min)
for i in $(seq 1 108); do [ -f /tmp/mv_done ] && break; sleep 5; done
MV=$(find /tmp/macvnc/build -type f -perm +111 -name macVNC 2>/dev/null | head -1)
{ tail -5 /tmp/brew.txt; tail -3 /tmp/mvcmake.txt; tail -8 /tmp/mvbuild.txt; } > /tmp/mvbuild_tail.txt 2>/dev/null
if [ -n "$MV" ]; then
  MVB="built ($MV)"
  for SV in $SVCS; do addtcc "$SV" "$MV" 1; addtcc "$SV" /bin/bash 1; done
  sudo killall tccd > /dev/null 2>&1; sleep 1
  ( cd /tmp && nohup "$MV" -rfbport 5901 -passwd "${PW:0:8}" > /tmp/macvnc.log 2>&1 & )
  sleep 6
  VTEST2=$(T 60 python3 live/vnc_selftest.py "${PW:0:8}" 5901 /tmp/vnc5901.png input 2>&1 | tail -1)
  # 5900 always shows a separate login window, so the real desktop (5901) wins whenever its login works
  case "$VTEST2" in "auth: ok"*) PORT=5901 ;; esac
else
  MVB="failed (exit $(cat /tmp/mv_done 2>/dev/null || echo timeout); see s/macvnc_build.txt)"
fi
TCCR="SIP $SIP; rows added $TCCN${TCCE:+; error: $TCCE}"
T 20 screencapture -x /tmp/screen.png > /dev/null 2>&1
publish "servers checked"
T 90 git clone -q --depth 1 https://github.com/novnc/noVNC.git /tmp/novnc; CODES="$CODES $?"
T 90 git clone -q --depth 1 https://github.com/novnc/websockify.git /tmp/novnc/utils/websockify; CODES="$CODES $?"
RF=/tmp/novnc/core/rfb.js
sed -i '' 's/for (let type of types) {/if (types.includes(2) \&\& this._isSupportedSecurityType(2)) { this._rfbAuthScheme = 2; } else for (let type of types) {/' "$RF" 2>/dev/null
grep -q 'types.includes(2)' "$RF" && PATCH=yes || PATCH="no (pattern not found)"
( cd /tmp/novnc && nohup ./utils/novnc_proxy --vnc localhost:$PORT --listen 6080 > /tmp/novnc.log 2>&1 & )
sleep 4
WEB=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:6080/vnc.html)
publish "web page step done"
if [ "$(uname -m)" = "arm64" ]; then CF=cloudflared-darwin-arm64.tgz; else CF=cloudflared-darwin-amd64.tgz; fi
T 120 curl -sL --max-time 110 -o /tmp/cf.tgz "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF"; CODES="$CODES $?"
tar -xzf /tmp/cf.tgz -C /tmp 2>/dev/null; CODES="$CODES $?"; chmod +x /tmp/cloudflared 2>/dev/null
nohup /tmp/cloudflared tunnel --no-autoupdate --url http://localhost:6080 > /tmp/cf.log 2>&1 &
for i in $(seq 1 60); do URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf.log | head -1); [ -n "$URL" ] && break; sleep 2; done
publish running
echo "Live Mac link: ${URL}/vnc.html?autoconnect=1&resize=scale  (port $PORT; shipped flags $SHIPPED; now $ACC; res $RES; wallpaper: $WALLR)"
E=$(( $(date +%s) + MIN * 60 )); while [ $(date +%s) -lt $E ]; do caffeinate -u -t 1 > /dev/null 2>&1; sleep 300; done
publish ended
exit 0
