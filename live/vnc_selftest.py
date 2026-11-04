# Live Mac self-test: logs in to this Mac's own Screen Sharing with the VNC (screen) password, exactly like
# the noVNC page does, watches ~8 s of frames, reports how much of each is not black, and saves the last
# frame as /tmp/vnc.png. Usage: python3 live/vnc_selftest.py <password>  (one line out; never prints it)
import socket, struct, subprocess, sys, time, zlib
pw = sys.argv[1].encode()[:8].ljust(8, b'\0')
key = bytes(int('{:08b}'.format(b)[::-1], 2) for b in pw)   # VNC uses DES with bit-reversed key bytes

def rx(s, n):
    b = bytearray()
    while len(b) < n:
        c = s.recv(min(1 << 20, n - len(b)))
        if not c:
            raise EOFError('closed after %d/%d bytes' % (len(b), n))
        b += c
    return bytes(b)

def des(block):
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

def save_png(path, w, h, fb):
    rgb = bytearray(w * h * 3)
    rgb[0::3] = fb[2::4]; rgb[1::3] = fb[1::4]; rgb[2::3] = fb[0::4]
    raw = b''.join(b'\x00' + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

def visible(fb):
    n = 0; tot = 0
    for i in range(0, len(fb), 28):
        tot += 1
        if fb[i] + fb[i + 1] + fb[i + 2] > 60:
            n += 1
    return 100.0 * n / max(1, tot)

try:
    s = socket.create_connection(('127.0.0.1', 5900), 10)
    s.settimeout(10)
    rx(s, 12)
    s.sendall(b'RFB 003.008\n')
    n = rx(s, 1)[0]
    if n == 0:
        raise RuntimeError('server refused: ' + rx(s, struct.unpack('>I', rx(s, 4))[0]).decode(errors='replace'))
    types = list(rx(s, n))
    if 2 not in types:
        raise RuntimeError('no screen-password type in %s' % types)
    s.sendall(b'\x02')
    s.sendall(des(rx(s, 16)))
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
    rx(s, struct.unpack('>I', rx(s, 4))[0])
    fb = bytearray(w * h * 4)
    s.sendall(b'\x00\x00\x00\x00' + struct.pack('>BBBBHHHBBB3x', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
    s.sendall(struct.pack('>BBHi', 2, 0, 1, 0))
    s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h))
    seen = []; t0 = time.time(); rects = 0
    while time.time() - t0 < 8:
        try:
            t = rx(s, 1)[0]
        except socket.timeout:
            seen.append('timeout'); break
        if t == 0:
            rx(s, 1)
            nr = struct.unpack('>H', rx(s, 2))[0]
            for _ in range(nr):
                x, y, rw, rh, enc = struct.unpack('>HHHHi', rx(s, 12))
                if enc != 0:
                    raise RuntimeError('non-raw encoding %d' % enc)
                data = rx(s, rw * rh * 4); rects += 1
                for row in range(rh):
                    o = ((y + row) * w + x) * 4
                    fb[o:o + rw * 4] = data[row * rw * 4:(row + 1) * rw * 4]
            seen.append('%.1f' % visible(fb))
            time.sleep(0.7)
            s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h))
        elif t == 2:
            continue
        elif t == 3:
            rx(s, 3)
            rx(s, struct.unpack('>I', rx(s, 4))[0])
        else:
            raise RuntimeError('unexpected message %d after %s' % (t, seen))
    save_png('/tmp/vnc.png', w, h, fb)
    print('auth: ok, screen %dx%d, %d updates (%d rects), visible %% per update: %s (frame saved as s/vnc.png)' % (w, h, len(seen), rects, ' '.join(seen[:12])))
except SystemExit:
    raise
except Exception as e:
    print('selftest error: %s' % e)
