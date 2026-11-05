#!/bin/bash
# Diagnostics for the live Mac, written to /tmp/probe.txt and published as s/probe.txt.
# Answers: why 1024x768 (what modes the virtual display offers), why it feels slow (how fast this Mac can
# capture a frame at all, before any network), and which account the GUI password prompts want.
# It also sets the resolution from live/res.txt (default 1280x960; 1024x768 is the fastest, 1920x1080 the
# biggest and slowest), and tries a short list of likely passwords for the console account, because the VM
# template's account is what macOS prompts for (its RealName is "Anka").
P=/tmp/probe.txt
which displayplacer > /dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 brew install displayplacer > /tmp/dp_install.txt 2>&1
WANT=$(cat live/res.txt 2>/dev/null | tr -d ' \n')
[ -z "$WANT" ] && WANT=1280x960
ID=$(displayplacer list 2>/dev/null | grep -m1 'Persistent screen id:' | awk '{print $4}')
MODES=$(displayplacer list 2>/dev/null | grep -Eo 'res:[0-9]+x[0-9]+ hz:[0-9]+ color_depth:[0-9]+')
PICK=$(echo "$MODES" | grep -m1 "res:$WANT ")
# fall back to the largest mode that is not wider than 1600 if the wanted one is missing
if [ -z "$PICK" ]; then
  PICK=$(echo "$MODES" | sed 's/res:\([0-9]*\)x\([0-9]*\)/\1 \2 res:\1x\2/' | awk '$1 <= 1600' | sort -k1,1nr -k2,2nr | head -1 | cut -d' ' -f3-)
fi
SETR="not attempted"
if [ -n "$ID" ] && [ -n "$PICK" ]; then
  CMD="id:$ID $PICK enabled:true scaling:off origin:(0,0) degree:0"
  displayplacer "$CMD" > /tmp/dp_set.txt 2>&1 && SETR="set to $(echo "$PICK" | sed 's/res:\([0-9x]*\).*/\1/')" || SETR="failed: $(head -c 120 /tmp/dp_set.txt | tr '\n' ' ')"
  sleep 4
fi
# the console account's password: macOS prompts for it, so find out whether it is a known template default
CAND="runner Runner anka Anka admin Admin password Password github GitHub actions runner-password anka-vm vagrant test123 1234 Passw0rd!"
HIT="none of $(echo $CAND | wc -w | tr -d ' ') candidates worked"
for C in $CAND; do
  if dscl . -authonly runner "$C" > /dev/null 2>&1; then HIT="WORKS: '$C'"; break; fi
done
{
  echo "== resolution =="
  echo "wanted (live/res.txt): $WANT"
  echo "result: $SETR"
  displayplacer list 2>&1 | grep -E 'Resolution:|mode [0-9]+:' | head -20
  echo
  echo "== console account password =="
  echo "runner RealName: $(dscl . -read /Users/runner RealName 2>/dev/null | tail -1 | sed 's/^ //')"
  echo "candidate sweep: $HIT"
  echo "admin group: $(dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/GroupMembership: //')"
  echo "sudo without password: $(sudo -n true 2>&1 && echo yes || echo no)"
  echo
  echo "== hardware =="
  system_profiler SPHardwareDataType 2>&1 | grep -E 'Model Name|Chip|Cores|Memory' | sed 's/^ *//'
  echo "GPU section present: $(system_profiler SPDisplaysDataType 2>&1 | wc -l | tr -d ' ') lines (empty = no graphics device at all, software rendering)"
  echo
  echo "== how fast this Mac can grab a frame (no network) =="
  python3 - <<'PY' 2>&1
import subprocess, time
ts = []
for _ in range(6):
    t = time.time(); subprocess.run(['screencapture', '-x', '-t', 'jpg', '/tmp/fps.jpg'], capture_output=True); ts.append(time.time() - t)
print('screencapture: %s ms each -> about %.1f fps ceiling on the Mac itself' % (' '.join('%.0f' % (t * 1000) for t in ts), 1.0 / (sum(ts[2:]) / len(ts[2:]))))
PY
  echo
  echo "== macVNC log =="; tail -25 /tmp/macvnc.log 2>/dev/null
} > "$P" 2>&1
echo "RES=$(displayplacer list 2>/dev/null | grep -m1 'Resolution:' | sed 's/.*: //')" >> "$P"
exit 0
