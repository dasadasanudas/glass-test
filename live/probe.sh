#!/bin/bash
# Diagnostics for the live Mac, written to /tmp/probe.txt and published as s/probe.txt.
# Answers: why 1024x768 (what display modes the virtual GPU offers), why it feels slow (how fast the Mac can
# capture and encode a frame at all), and which account the GUI password prompts want.
P=/tmp/probe.txt
{
  echo "== display =="
  system_profiler SPDisplaysDataType 2>&1 | head -40
  echo
  echo "== display modes (displayplacer) =="
  if ! which displayplacer > /dev/null 2>&1; then HOMEBREW_NO_AUTO_UPDATE=1 brew install displayplacer > /tmp/dp_install.txt 2>&1; fi
  displayplacer list 2>&1 | head -60
  echo
  echo "== GPU / renderer =="
  system_profiler SPHardwareDataType 2>&1 | head -20
  echo "metal: $(system_profiler SPDisplaysDataType 2>&1 | grep -i metal | head -2 | tr '\n' ' ')"
  echo
  echo "== accounts =="
  echo "console user: $(stat -f %Su /dev/console)"
  echo "whoami: $(whoami)"
  for U in $(dscl . -list /Users | grep -v '^_' | grep -v daemon | grep -v nobody); do
    echo "user $U: realname '$(dscl . -read /Users/$U RealName 2>/dev/null | tail -1 | sed 's/^ //')' uid $(dscl . -read /Users/$U UniqueID 2>/dev/null | awk '{print $2}') securetoken $(sysadminctl -secureTokenStatus $U 2>&1 | grep -Eo 'ENABLED|DISABLED')"
  done
  echo "admin group: $(dscl . -read /Groups/admin GroupMembership 2>/dev/null)"
  echo "sudo without password: $(sudo -n true 2>&1 && echo yes || echo no)"
  echo
  echo "== authorization rights (what GUI prompts check) =="
  for R in system.preferences system.preferences.accessibility system.install.apple-software system.privilege.admin; do
    echo "$R -> $(security authorizationdb read $R 2>/dev/null | grep -A1 -E '<key>(class|rule)</key>' | tr '\n' ' ' | head -c 120)"
  done
  echo
  echo "== how fast this Mac can grab a frame (no network) =="
  python3 - <<'PY' 2>&1
import subprocess, time
ts = []
for _ in range(5):
    t = time.time(); subprocess.run(['screencapture', '-x', '-t', 'jpg', '/tmp/fps.jpg'], capture_output=True); ts.append(time.time() - t)
print('screencapture: %s ms each -> about %.1f fps ceiling' % (' '.join('%.0f' % (t * 1000) for t in ts), 1.0 / (sum(ts) / len(ts))))
PY
  echo "macVNC log:"; tail -20 /tmp/macvnc.log 2>/dev/null
} > "$P" 2>&1
# try the biggest offered mode, so the session is not stuck at 1024x768
BEST=$(displayplacer list 2>/dev/null | grep -Eo 'res:[0-9]+x[0-9]+ hz:[0-9]+ color_depth:[0-9]+ scaling:off' | sed 's/res:\([0-9]*\)x\([0-9]*\).*/\1 \2 &/' | sort -k1,1nr -k2,2nr | head -1)
if [ -n "$BEST" ]; then
  W=$(echo "$BEST" | awk '{print $1}'); H=$(echo "$BEST" | awk '{print $2}')
  ID=$(displayplacer list 2>/dev/null | grep -Eo 'Persistent screen id: [^ ]+' | head -1 | awk '{print $4}')
  if [ -n "$ID" ] && [ "${W:-0}" -gt 1024 ]; then
    displayplacer "id:$ID res:${W}x${H} scaling:off origin:(0,0) degree:0" >> "$P" 2>&1
    sleep 3
    echo "after displayplacer: $(system_profiler SPDisplaysDataType 2>&1 | grep -i resolution | head -2 | tr '\n' ' ')" >> "$P"
  fi
fi
echo "RES=$(system_profiler SPDisplaysDataType 2>&1 | grep -i -m1 resolution | sed 's/.*: //')" >> "$P"
exit 0
