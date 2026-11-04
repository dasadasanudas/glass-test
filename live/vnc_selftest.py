# Live Mac self-test: logs in to this Mac's own Screen Sharing with the VNC (screen) password, exactly like
# the noVNC page does, then grabs one full frame and reports how much of it is not black.
# Usage: python3 live/vnc_selftest.py <password>   (prints one line; never prints the password)
import socket, struct, subprocess, sys
pw = sys.argv[1].encode()[:8].ljust(8, b'\0')
key = bytes(int('{:08b}'.format(b)[::-1], 2) for b in pw)   # VNC uses DES with bit-reversed key bytes

def rx(s, n):
    b = b''
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise EOFError('closed after %d/%d bytes' % (len(b), n))
        b += c
    return b

def des(block):
    # macOS ships LibreSSL at /usr/bin/openssl (DES built in); Homebrew OpenSSL 3 needs the legacy provider
    errs = []
    for cmd in (['/usr/bin/openssl', 'enc', '-des-ecb'], ['openssl', 'enc', '-des-ecb', '-provider', 'legacy', '-provider', 'default'], ['openssl', 'enc', '-des-ecb']):
        try:
            r = subprocess.run(cmd + ['-K', key.hex(), '-nopad', '-nosalt'], input=block, capture_output=True)
        except Exception as e:
            errs.append(str(e)[:40]); continue
        if r.returncode == 0 and len(r.stdout) == 16:
            return r.stdout
        errs.append(r.stderr.decode(errors='replace').strip().split('\n')[-1][:60])
    raise RuntimeError('des failed: ' + ' | '.join(errs))

try:
    s = socket.create_connection(('127.0.0.1', 5900), 10)
    s.settimeout(20)
    ver = rx(s, 12)
    s.sendall(b'RFB 003.008\n')
    n = rx(s, 1)[0]
    if n == 0:
        raise RuntimeError('server refused: ' + rx(s, struct.unpack('>I', rx(s, 4))[0]).decode(errors='replace'))
    types = list(rx(s, n))
    if 2 not in types:
        raise RuntimeError('no screen-password type in %s' % types)
    s.sendall(b'\x02')
    ch = rx(s, 16)
    s.sendall(des(ch))
    res = struct.unpack('>I', rx(s, 4))[0]
    if res != 0:
        reason = ''
        try:
            reason = rx(s, struct.unpack('>I', rx(s, 4))[0]).decode(errors='replace')
        except Exception:
            pass
        print('auth: REJECTED (%d) %s' % (res, reason))
        sys.exit(0)
    s.sendall(b'\x01')
    w, h = struct.unpack('>HH', rx(s, 4))
    rx(s, 16)
    name = rx(s, struct.unpack('>I', rx(s, 4))[0]).decode(errors='replace')
    pf = struct.pack('>BBBBHHHBBB3x', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    s.sendall(b'\x00\x00\x00\x00' + pf)
    s.sendall(struct.pack('>BBHi', 2, 0, 1, 0))
    s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h))
    bright = 0
    total = 0
    while True:
        t = rx(s, 1)[0]
        if t == 0:
            rx(s, 1)
            nr = struct.unpack('>H', rx(s, 2))[0]
            for _ in range(nr):
                x, y, rw, rh, enc = struct.unpack('>HHHHi', rx(s, 12))
                if enc != 0:
                    raise RuntimeError('non-raw encoding %d' % enc)
                data = rx(s, rw * rh * 4)
                total += rw * rh
                for i in range(0, len(data), 28):
                    if data[i] + data[i + 1] + data[i + 2] > 60:
                        bright += 1
            break
        elif t == 2:
            continue
        elif t == 3:
            rx(s, 3)
            rx(s, struct.unpack('>I', rx(s, 4))[0])
        else:
            raise RuntimeError('unexpected message %d' % t)
    print('auth: ok, screen %dx%d "%s", visible (non-black) pixels: %.1f%%' % (w, h, name, bright * 7 * 100.0 / max(1, total)))
except SystemExit:
    raise
except Exception as e:
    print('selftest error: %s' % e)
