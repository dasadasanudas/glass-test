#!/usr/bin/env python3
# Test wallpapers (1024x768, sRGB, no profile) for measuring the system glass: flat bands, 32 pt colour tiles, a 16 pt checker.
import zlib, struct, sys, os
W, H = 1024, 768
def png(path, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))
BANDS = [(0, 184, (245, 245, 245)), (184, 260, (16, 16, 16)), (260, 336, (128, 128, 128)), (336, 412, (30, 100, 220)), (412, 490, (240, 140, 40)), (490, 690, (40, 140, 70))]
DOCK = [(245, 245, 245), (16, 16, 16), (128, 128, 128), (30, 100, 220), (240, 140, 40), (40, 140, 70), (200, 60, 160), (90, 90, 90)]
def bands():
    rows = []
    for y in range(H):
        if y >= 690:
            r = bytearray()
            for x in range(W): r += bytes(DOCK[x // 128])
        else:
            c = next(c for a, b, c in BANDS if a <= y < b); r = bytearray(bytes(c) * W)
        rows.append(r)
    return rows
def tiles():
    seed = 12345; pal = []
    for i in range(32 * 24):
        seed = (seed * 1103515245 + 12345) & 0x7fffffff; a = seed
        pal.append(((a >> 3) % 256, (a >> 11) % 256, (a >> 19) % 256))
    rows = []
    for y in range(H):
        r = bytearray()
        for tx in range(32): r += bytes(pal[(y // 32) * 32 + tx]) * 32
        rows.append(r)
    return rows
def check():
    rows = []
    for y in range(H):
        r = bytearray()
        for tx in range(64): v = 220 if (tx + y // 16) % 2 == 0 else 40; r += bytes((v, v, v)) * 16
        rows.append(r)
    return rows
out = sys.argv[1] if len(sys.argv) > 1 else '.'
for n, f in (('bands', bands), ('tiles', tiles), ('check', check)):
    p = os.path.join(out, 'wall_%s.png' % n); png(p, f()); print(p, os.path.getsize(p))
