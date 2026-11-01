# Independent extraction of Apple's shader modules from a .metallib (fat or thin).
# usage: python3 air_dump.py <metallib> <outdir> [llvm-dis path]
import sys, os, struct, re, hashlib, subprocess
src, out = sys.argv[1], sys.argv[2]
dis = sys.argv[3] if len(sys.argv) > 3 else ''
os.makedirs(os.path.join(out, 'bc'), exist_ok=True); os.makedirs(os.path.join(out, 'll'), exist_ok=True)
data = open(src, 'rb').read()
print('file', src, len(data), 'sha256', hashlib.sha256(data).hexdigest())
slices = []
mg = struct.unpack('>I', data[:4])[0]
if data[:4] == b'MTLB':
    slices.append((0, len(data), 'thin'))
elif mg in (0xCAFEBABE, 0xCAFEBABF):
    n = struct.unpack('>I', data[4:8])[0]
    print('fat archs', n)
    for i in range(n):
        if mg == 0xCAFEBABE:
            ct, cs, off, size, al = struct.unpack('>iiIII', data[8 + 20 * i: 28 + 20 * i])
        else:
            ct, cs, off, size, al, _ = struct.unpack('>iiQQII', data[8 + 32 * i: 40 + 32 * i])
        tag = data[off:off + 4]
        print(' arch %d cputype 0x%x sub 0x%x off %d size %d magic %r' % (i, ct & 0xffffffff, cs & 0xffffffff, off, size, tag))
        if tag == b'MTLB': slices.append((off, size, 'arch%d_0x%x' % (i, ct & 0xffffffff)))
else:
    i = data.find(b'MTLB'); print('unknown container, first MTLB at', i)
    if i >= 0: slices.append((i, len(data) - i, 'scan'))
PAT = re.compile(r'(glass|sdf|downsample|blur|fixed|mip|gauss|surface|kawase|backdrop|highlight|vibrant|ds4|Xghfc|A2X|Bvcm|Tkfh|Timg|pyramid|reduce|resolve)', re.I)
allnames = []
for (base, size, tag) in slices:
    h = data[base:base + 0x58]
    magic, plat, vmaj, vmin, ftype, os_, osmaj, osmin = struct.unpack('<4sHHHBBHH', h[:16])
    fsize, flo, fls, pmo, pms, qmo, qms, bco, bcs = struct.unpack('<9Q', h[16:88])
    print('slice %s base %d plat 0x%x ver %d.%d type %d os %d %d.%d fsize %d funclist %d+%d pub %d+%d priv %d+%d bitcode %d+%d' % (tag, base, plat, vmaj, vmin, ftype, os_, osmaj, osmin, fsize, flo, fls, pmo, pms, qmo, qms, bco, bcs))
    p = base + flo
    cnt = struct.unpack('<I', data[p:p + 4])[0]; p += 4
    print('functions', cnt)
    funcs = []
    for fi in range(cnt):
        esz = struct.unpack('<I', data[p:p + 4])[0]
        q = p + 4; end = p + esz if esz > 4 else p + 4 + 4096
        rec = {'i': fi}
        found_end = False
        while q < end + 8:
            t = data[q:q + 4]; q += 4
            if t == b'ENDT': found_end = True; break
            ln = struct.unpack('<H', data[q:q + 2])[0]; q += 2
            v = data[q:q + ln]; q += ln
            if t == b'NAME': rec['name'] = v.split(b'\0')[0].decode('utf-8', 'replace')
            elif t == b'TYPE': rec['type'] = v[0]
            elif t == b'HASH': rec['hash'] = v.hex()
            elif t == b'MDSZ': rec['mdsz'] = struct.unpack('<Q', v[:8])[0]
            elif t == b'OFFT': rec['offt'] = struct.unpack('<3Q', v[:24])
            else: rec.setdefault('tags', []).append(t.decode('latin1'))
        p = q if found_end else p + esz
        funcs.append(rec)
        if fi < 3: print('  entry', fi, 'size field', esz, 'rec', {k: rec[k] for k in rec if k != 'hash'})
    for r in funcs:
        allnames.append('%s\t%d\t%s\t%s\t%s' % (tag, r['i'], r.get('name'), r.get('type'), r.get('mdsz')))
    sel = [r for r in funcs if r.get('name') and (PAT.search(r['name']) or r.get('type') == 2)]
    print('selected', len(sel), 'of', len(funcs))
    for r in sel:
        if 'offt' not in r or 'mdsz' not in r: continue
        off = base + bco + r['offt'][2]; bc = data[off:off + r['mdsz']]
        nm = re.sub(r'[^A-Za-z0-9_.]', '_', r['name'])[:80]
        fn = '%s__%05d__%s' % (tag, r['i'], nm)
        open(os.path.join(out, 'bc', fn + '.bc'), 'wb').write(bc)
        ok = bc[:4] in (b'\xde\xc0\x17\x0b', b'BC\xc0\xde')
        sha = hashlib.sha256(bc).hexdigest()
        llok = ''
        if dis and os.path.exists(dis) and ok:
            try:
                rr = subprocess.run([dis, os.path.join(out, 'bc', fn + '.bc'), '-o', os.path.join(out, 'll', fn + '.ll')], capture_output=True, timeout=120)
                llok = 'll' if rr.returncode == 0 else ('dis_err ' + rr.stderr.decode()[:160].replace('\n', ' '))
            except Exception as e:
                llok = 'dis_exc ' + str(e)[:100]
        print('  %5d %-60s type %s size %d bcmagic %s sha %s %s' % (r['i'], r['name'][:60], r.get('type'), len(bc), ok, sha[:16], llok))
open(os.path.join(out, 'functions.txt'), 'w').write('\n'.join(allnames) + '\n')
print('total names', len(allnames))
