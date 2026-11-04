#!/bin/bash
# Live Mac: turns on Screen Sharing on this runner, serves it as a web page (noVNC) and opens a public
# HTTPS link (Cloudflare quick tunnel). Progress and the link go to s/status.txt on the live-status branch
# and the job log. Stop it by cancelling the run.
# Login: the page should ask for a Password only: type the first 8 characters of LIVE_MAC_PASSWORD. That
# is the screen password and shows runner's own logged-in desktop. (Username logins: runner's password
# cannot be changed because the account has a secure token; livemac works but opens its own black session.)
# Nov 4 run 4: noVNC follows the server's order and macOS offers Apple auth first, so it asked for a
# username. noVNC is now patched to pick the plain VNC password when the Mac offers it.
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
MIN="${MINUTES:-}"; [ -z "$MIN" ] && MIN=$(cat live/minutes.txt 2>/dev/null || echo 60)
MIN=$(( MIN > 340 ? 340 : MIN ))
if [ -n "$LIVE_PASSWORD" ]; then PW="$LIVE_PASSWORD"; NOTE="password: your LIVE_MAC_PASSWORD secret"
else PW=$(openssl rand -hex 4); NOTE="no LIVE_MAC_PASSWORD secret set: a random password was used (only the test key can read it)"; fi
echo "::add-mask::$PW"
ME=$(whoami); A=livemac; U="$ME"
START=$(date -u '+%Y-%m-%d %H:%M'); END=$(date -u -v+${MIN}M '+%Y-%m-%d %H:%M' 2>/dev/null)
URL=""; VNC="?"; WEB="?"; CODES=""; CONSOLE="?"; SHOT="none"; PWCHK="?"; PWCHK2="?"; TOK="?"; VPW="?"; SECT="?"; PATCH="?"
publish() {
  D=$(mktemp -d); mkdir -p "$D/s"
  {
    echo "state: $1"
    echo "link: ${URL:-none}/vnc.html?autoconnect=1&resize=scale"
    echo "login: Password only -> first 8 characters of your secret (runner's screen)"
    echo "auth types the Mac offers (2 = screen password, 30 = Apple username login): $SECT"
    echo "noVNC prefers screen password: $PATCH"
    echo "password check $ME: $PWCHK"
    echo "password check $A: $PWCHK2"
    echo "secure token $ME: $TOK"
    echo "screen (VNC) password file: $VPW"
    echo "screen sharing: $VNC"
    echo "web page (local check): $WEB"
    echo "console user: $CONSOLE"
    echo "local screenshot: $SHOT (s/screen.png)"
    echo "step exit codes: $CODES"
    echo "minutes: $MIN"
    echo "started (UTC): $START"
    echo "ends about (UTC): $END"
    echo "run: ${GITHUB_RUN_ID:-?}"
    echo "machine: $(uname -m) $(sw_vers -productVersion 2>/dev/null)"
    echo "$NOTE"
    if [ -z "$LIVE_PASSWORD" ] && [ -f live/test_pub.pem ]; then echo "test: $(printf %s "$PW" | openssl pkeyutl -encrypt -pubin -inkey live/test_pub.pem 2>/dev/null | base64 | tr -d '\n')"; fi
  } > "$D/s/status.txt"
  [ -f /tmp/screen.png ] && cp /tmp/screen.png "$D/s/screen.png"
  ( cd "$D" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b live-status && git add s && git commit -qm "live mac $1" && T 60 git -c credential.helper= -c core.askPass= push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" live-status ) > /dev/null 2>&1 || echo "publish failed ($1)"
}
publish starting
# keep the console display awake for the whole session
T 20 sudo pmset -a displaysleep 0 sleep 0 disksleep 0 > /tmp/pm.txt 2>&1; CODES="$CODES $?"
nohup caffeinate -dimsu -t $(( MIN * 60 + 900 )) > /dev/null 2>&1 &
T 10 caffeinate -u -t 3 > /dev/null 2>&1
T 20 defaults -currentHost write com.apple.screensaver idleTime -int 0 > /tmp/ss1.txt 2>&1; CODES="$CODES $?"
T 20 sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime -int 0 > /tmp/ss2.txt 2>&1; CODES="$CODES $?"
T 20 sudo defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 0 > /tmp/ss3.txt 2>&1; CODES="$CODES $?"
# accounts
TOK=$(T 20 sudo sysadminctl -secureTokenStatus "$ME" 2>&1 | grep -Eo 'ENABLED|DISABLED' | head -1)
T 90 sudo sysadminctl -addUser "$A" -fullName "Live Mac" -password "$PW" -admin > /tmp/acct1.txt 2>&1; CODES="$CODES $?"
T 30 sudo dscl . -passwd "/Users/$ME" "$PW" > /tmp/acct3.txt 2>&1; CODES="$CODES $?"
chk() { T 20 dscl /Local/Default -authonly "$1" "$PW" > /tmp/chk_$1.txt 2>&1 && echo ok || echo "failed ($(head -c 100 /tmp/chk_$1.txt | tr '\n' ' '))"; }
PWCHK=$(chk "$ME")
if [ "${PWCHK%% *}" != "ok" ]; then
  T 90 sudo sysadminctl -resetPasswordFor "$ME" -newPassword "$PW" -adminUser "$A" -adminPassword "$PW" > /tmp/acct2.txt 2>&1; CODES="$CODES $?"
  PWCHK=$(chk "$ME")
fi
PWCHK2=$(chk "$A")
# screen sharing access: access group plus all users allowed
T 20 sudo dseditgroup -o create -q com.apple.access_screensharing > /tmp/grp0.txt 2>&1; CODES="$CODES $?"
T 20 sudo dseditgroup -o edit -a "$ME" -t user com.apple.access_screensharing > /tmp/grp1.txt 2>&1; CODES="$CODES $?"
T 20 sudo dseditgroup -o edit -a "$A" -t user com.apple.access_screensharing > /tmp/grp2.txt 2>&1; CODES="$CODES $?"
K=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
T 60 sudo "$K" -configure -allowAccessFor -allUsers -privs -all > /tmp/share0.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -configure -access -on -users "$ME,$A" -privs -all > /tmp/share1.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw "${PW:0:8}" > /tmp/share2.txt 2>&1; CODES="$CODES $?"
# legacy VNC (screen) password written directly, in Apple's obfuscated format (first 8 characters)
printf %s "${PW:0:8}" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA" } $_ = <STDIN>; $_ = "" unless defined; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) } print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null 2>/tmp/vpw.txt; R=$?; CODES="$CODES $R"
T 10 sudo chmod 600 /Library/Preferences/com.apple.VNCSettings.txt > /dev/null 2>&1
[ "$R" = "0" ] && VPW="written ($(sudo wc -c /Library/Preferences/com.apple.VNCSettings.txt 2>/dev/null | awk '{print $1}') bytes)" || VPW="failed"
T 20 sudo defaults write /Library/Preferences/com.apple.RemoteManagement VNCLegacyConnectionsEnabled -bool true > /tmp/share2b.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -restart -agent -console > /tmp/share3.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -activate > /tmp/share4.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl enable system/com.apple.screensharing > /tmp/share5.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist > /tmp/share6.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl kickstart -k system/com.apple.screensharing > /tmp/share7.txt 2>&1; CODES="$CODES $?"
sleep 3
VNC=$(T 5 nc -z localhost 5900 >/dev/null 2>&1 && echo up || echo down)
# which logins does the Mac offer? (RFB handshake: version, then the list of security types)
SECT=$(T 10 python3 -c "import socket; s=socket.create_connection(('127.0.0.1',5900),5); v=s.recv(12); s.sendall(b'RFB 003.008\n'); n=s.recv(1)[0]; print(v.decode().strip(), list(s.recv(n)))" 2>&1 | tail -1)
CONSOLE=$(stat -f %Su /dev/console 2>/dev/null)
T 10 caffeinate -u -t 2 > /dev/null 2>&1
T 20 screencapture -x /tmp/screen.png > /tmp/shot.txt 2>&1 && SHOT="taken $(stat -f %z /tmp/screen.png 2>/dev/null) bytes" || SHOT="failed"
publish "screen sharing step done"
T 90 git clone -q --depth 1 https://github.com/novnc/noVNC.git /tmp/novnc; CODES="$CODES $?"
T 90 git clone -q --depth 1 https://github.com/novnc/websockify.git /tmp/novnc/utils/websockify; CODES="$CODES $?"
# noVNC takes the first type in the Mac's own order (Apple username login); make it take the screen password
RF=/tmp/novnc/core/rfb.js
sed -i '' 's/for (let type of types) {/if (types.includes(2) \&\& this._isSupportedSecurityType(2)) { this._rfbAuthScheme = 2; } else for (let type of types) {/' "$RF" 2>/dev/null
grep -q 'types.includes(2)' "$RF" && PATCH=yes || PATCH="no (pattern not found)"
( cd /tmp/novnc && nohup ./utils/novnc_proxy --vnc localhost:5900 --listen 6080 > /tmp/novnc.log 2>&1 & )
sleep 4
WEB=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:6080/vnc.html)
publish "web page step done"
if [ "$(uname -m)" = "arm64" ]; then CF=cloudflared-darwin-arm64.tgz; else CF=cloudflared-darwin-amd64.tgz; fi
T 120 curl -sL --max-time 110 -o /tmp/cf.tgz "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF"; CODES="$CODES $?"
tar -xzf /tmp/cf.tgz -C /tmp 2>/dev/null; CODES="$CODES $?"; chmod +x /tmp/cloudflared 2>/dev/null
nohup /tmp/cloudflared tunnel --no-autoupdate --url http://localhost:6080 > /tmp/cf.log 2>&1 &
for i in $(seq 1 60); do URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf.log | head -1); [ -n "$URL" ] && break; sleep 2; done
publish running
echo "Live Mac link: ${URL}/vnc.html?autoconnect=1&resize=scale  (auth types: $SECT; noVNC patch: $PATCH; vnc file: $VPW)"
# nudge the display every 5 minutes so it never idles to black
E=$(( $(date +%s) + MIN * 60 )); while [ $(date +%s) -lt $E ]; do caffeinate -u -t 1 > /dev/null 2>&1; sleep 300; done
publish ended
exit 0
