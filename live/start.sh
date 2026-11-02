#!/bin/bash
# Live Mac: turns on Screen Sharing on this runner, serves it as a web page (noVNC) and opens a public
# HTTPS link (Cloudflare quick tunnel). Progress and the link go to s/status.txt on the live-status branch
# and the job log. Log in with the username shown there and your password. Stop it by cancelling the run.
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
MIN="${MINUTES:-}"; [ -z "$MIN" ] && MIN=$(cat live/minutes.txt 2>/dev/null || echo 60)
MIN=$(( MIN > 340 ? 340 : MIN ))
if [ -n "$LIVE_PASSWORD" ]; then PW="$LIVE_PASSWORD"; NOTE="password: your LIVE_MAC_PASSWORD secret"
else PW=$(openssl rand -hex 4); NOTE="no LIVE_MAC_PASSWORD secret set: a random password was used (only the test key can read it)"; fi
echo "::add-mask::$PW"
U=$(whoami)
START=$(date -u '+%Y-%m-%d %H:%M'); END=$(date -u -v+${MIN}M '+%Y-%m-%d %H:%M' 2>/dev/null)
URL=""; VNC="?"; WEB="?"; CODES=""
T 30 gh auth setup-git >/dev/null 2>&1 || true
publish() {
  D=$(mktemp -d); mkdir -p "$D/s"
  {
    echo "state: $1"
    echo "link: ${URL:-none}/vnc.html?autoconnect=1&resize=scale"
    echo "username: $U"
    echo "screen sharing: $VNC"
    echo "web page (local check): $WEB"
    echo "step exit codes: $CODES"
    echo "minutes: $MIN"
    echo "started (UTC): $START"
    echo "ends about (UTC): $END"
    echo "machine: $(uname -m) $(sw_vers -productVersion 2>/dev/null)"
    echo "$NOTE"
    if [ -z "$LIVE_PASSWORD" ] && [ -f live/test_pub.pem ]; then echo "test: $(printf %s "$PW" | openssl pkeyutl -encrypt -pubin -inkey live/test_pub.pem 2>/dev/null | base64 | tr -d '\n')"; fi
  } > "$D/s/status.txt"
  ( cd "$D" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b live-status && git add s && git commit -qm "live mac $1" && T 60 git push -q -f "https://github.com/${REPO}.git" live-status ) || echo "publish failed"
}
publish starting
T 30 sudo dscl . -passwd "/Users/$U" "$PW" > /tmp/acct.txt 2>&1; CODES="$CODES $?"
K=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
T 60 sudo "$K" -configure -allowAccessFor -allUsers -privs -all > /tmp/share1.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw "${PW:0:8}" > /tmp/share2.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -restart -agent -console > /tmp/share3.txt 2>&1; CODES="$CODES $?"
T 60 sudo "$K" -activate > /tmp/share4.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl enable system/com.apple.screensharing > /tmp/share5.txt 2>&1; CODES="$CODES $?"
T 20 sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist > /tmp/share6.txt 2>&1; CODES="$CODES $?"
sleep 3
VNC=$(T 5 nc -z localhost 5900 >/dev/null 2>&1 && echo up || echo down)
publish "screen sharing step done"
T 90 git clone -q --depth 1 https://github.com/novnc/noVNC.git /tmp/novnc; CODES="$CODES $?"
T 90 git clone -q --depth 1 https://github.com/novnc/websockify.git /tmp/novnc/utils/websockify; CODES="$CODES $?"
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
echo "Live Mac link: ${URL}/vnc.html?autoconnect=1&resize=scale  (username: $U, screen sharing: $VNC, page: $WEB)"
sleep $(( MIN * 60 ))
publish ended
exit 0
