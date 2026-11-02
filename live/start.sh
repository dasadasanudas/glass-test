#!/bin/bash
# Live Mac: turns on Screen Sharing on this runner, serves it as a web page (noVNC) and opens a public
# HTTPS link (Cloudflare quick tunnel). The link is written to s/status.txt on the live-status branch
# and printed in the job log. Stop it any time by cancelling the run in the Actions tab.
export HOMEBREW_NO_AUTO_UPDATE=1
MIN="${MINUTES:-}"; [ -z "$MIN" ] && MIN=$(cat live/minutes.txt 2>/dev/null || echo 60)
MIN=$(( MIN > 340 ? 340 : MIN ))
if [ -n "$LIVE_PASSWORD" ]; then PW="${LIVE_PASSWORD:0:8}"; NOTE="password: your LIVE_MAC_PASSWORD secret (first 8 characters)"
else PW=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8); NOTE="no LIVE_MAC_PASSWORD secret set: a random password was used (only the test key can read it)"; fi
echo "::add-mask::$PW"
START=$(date -u '+%Y-%m-%d %H:%M'); END=$(date -u -v+${MIN}M '+%Y-%m-%d %H:%M' 2>/dev/null)
K=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
{
  sudo "$K" -configure -allowAccessFor -allUsers -privs -all
  sudo "$K" -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw "$PW"
  sudo "$K" -restart -agent -console
  sudo "$K" -activate
  sudo launchctl enable system/com.apple.screensharing
  sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist
} > /tmp/share.txt 2>&1
sleep 5
VNC=$(nc -z localhost 5900 >/dev/null 2>&1 && echo up || echo down)
git clone -q --depth 1 https://github.com/novnc/noVNC.git /tmp/novnc
git clone -q --depth 1 https://github.com/novnc/websockify.git /tmp/novnc/utils/websockify
( cd /tmp/novnc && nohup ./utils/novnc_proxy --vnc localhost:5900 --listen 6080 > /tmp/novnc.log 2>&1 & )
brew install -q cloudflared > /tmp/brew.txt 2>&1 || true
nohup cloudflared tunnel --no-autoupdate --url http://localhost:6080 > /tmp/cf.log 2>&1 &
URL=""
for i in $(seq 1 90); do URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf.log | head -1); [ -n "$URL" ] && break; sleep 2; done
WEB=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:6080/vnc.html)
gh auth setup-git >/dev/null 2>&1 || true
publish() {
  D=$(mktemp -d); mkdir -p "$D/s"
  {
    echo "state: $1"
    echo "link: ${URL:-none}/vnc.html?autoconnect=1&resize=scale"
    echo "screen sharing: $VNC"
    echo "web page (local check): $WEB"
    echo "minutes: $MIN"
    echo "started (UTC): $START"
    echo "ends about (UTC): $END"
    echo "$NOTE"
    if [ -z "$LIVE_PASSWORD" ] && [ -f live/test_pub.pem ]; then echo "test: $(printf %s "$PW" | openssl pkeyutl -encrypt -pubin -inkey live/test_pub.pem | base64 | tr -d '\n')"; fi
  } > "$D/s/status.txt"
  ( cd "$D" && git init -q && git config user.name lgx-bot && git config user.email lgx-bot@users.noreply.github.com && git checkout -q -b live-status && git add s && git commit -qm "live mac $1" && git push -q -f "https://github.com/${REPO}.git" live-status ) || echo "publish failed"
}
publish running
echo "Live Mac link: ${URL}/vnc.html?autoconnect=1&resize=scale  (screen sharing: $VNC, page: $WEB)"
sleep $(( MIN * 60 ))
publish ended
exit 0
