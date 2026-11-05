# Live Mac self-test: logs in to a VNC server on this Mac with the screen password, exactly like the noVNC
# page does, watches ~6 s of frames, reports how much of each is not black, and saves the last frame.
# With 'input', it then clicks the Apple menu over VNC (up to 3 tries), measures how many pixels changed,
# and presses Escape.
# Usage: python3 live/vnc_selftest.py <password> [port] [png] [input]  (one line out; never prints it)
import socket, struct, subprocess, sys, time, zlib
pw = sys.argv[1].encode()[:8].ljust(8, b'\0')
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 5900
OUT = sys.argv[3] if len(sys.argv) > 3 else '/tmp/vnc.png'
INPUT = len(sys.argv) > 4 and sys.argv[4] == 'input'
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

def changed(a, b):
    # percent of sampled pixels whose colour moved by more than 40 (sum of channels); works on any wallpaper
    n = 0; tot = 0
    for i in range(0, min(len(a), len(b)), 16):
        tot += 1
        if abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2]) > 40:
            n += 1
    return 100.0 * n / max(1, tot)

try:
    s = socket.create_connection(('127.0.0.1', PORT), 10)
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
        print('auth: REJECTED (%d) %s | LAST=0' % (res, reason))
        sys.exit(0)
    s.sendall(b'\x01')
    w, h = struct.unpack('>HH', rx(s, 4))
    rx(s, 16)
    rx(s, struct.unpack('>I', rx(s, 4))[0])
    fb = bytearray(w * h * 4)
    s.sendall(b'\x00\x00\x00\x00' + struct.pack('>BBBBHHHBBB3x', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
    s.sendall(struct.pack('>BBHi', 2, 0, 1, 0))

    def frame():
        s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h))
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
                    for row in range(rh):
                        o = ((y + row) * w + x) * 4
                        fb[o:o + rw * 4] = data[row * rw * 4:(row + 1) * rw * 4]
                return visible(fb)
            elif t == 2:
                continue
            elif t == 3:
                rx(s, 3)
                rx(s, struct.unpack('>I', rx(s, 4))[0])
            else:
                raise RuntimeError('unexpected message %d' % t)

    seen = []
    for _ in range(6):
        seen.append('%.1f' % frame())
        time.sleep(0.6)
    save_png(OUT, w, h, fb)
    last = float(seen[-1])
    extra = ''
    if INPUT:
        tries = []
        ok = False
        for attempt in range(3):
            s.sendall(struct.pack('>BBHH', 5, 0, 300, 300)); time.sleep(0.4)      # wiggle away first
            s.sendall(struct.pack('>BBHH', 5, 0, 30, 14)); time.sleep(0.6)        # move to the Apple menu
            frame(); f0 = bytes(fb)
            s.sendall(struct.pack('>BBHH', 5, 1, 30, 14)); time.sleep(0.35)       # press (longer hold)
            s.sendall(struct.pack('>BBHH', 5, 0, 30, 14)); time.sleep(1.8)        # release
            frame(); f1 = bytes(fb)
            c1 = changed(f0, f1)
            if c1 > 0.5:
                save_png(OUT.replace('.png', '_menu.png'), w, h, fb)
                s.sendall(struct.pack('>BBxxI', 4, 1, 0xff1b)); s.sendall(struct.pack('>BBxxI', 4, 0, 0xff1b)); time.sleep(1.2)   # Escape
                frame(); f2 = bytes(fb)
                c2 = changed(f1, f2)
                tries.append('try %d: click %.1f%%, Escape %.1f%%' % (attempt + 1, c1, c2))
                ok = c2 > 0.5
                break
            tries.append('try %d: click %.1f%%' % (attempt + 1, c1))
            if attempt == 2:
                save_png(OUT.replace('.png', '_menu.png'), w, h, fb)
            time.sleep(1.0)
        extra = ' | input: %s (%s)' % ('works' if ok else 'NOT confirmed', '; '.join(tries))
    print('auth: ok, screen %dx%d, visible %% per frame: %s%s | LAST=%.1f' % (w, h, ' '.join(seen), extra, last))
except SystemExit:
    raise
except Exception as e:
    print('selftest error: %s | LAST=0' % e)
