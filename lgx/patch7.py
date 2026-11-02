# Run 7: reuses the run-5 edits (patch5.py). Renders NSGlassEffectView with the public style property
# (0 = regular, 1 = clear) and no variant, and logs which material number each style ends up with.
import sys
src = open('lgx/patch5.py').read()
src = src.replace('static int gNoHL = 0;', 'static int gNoHL = 0;\nstatic long gStyle = -1;')
old = '    if (variant >= 0) { @try { [g setValue:@(variant) forKey:@"_variant"]; }'
new = ('    if (gStyle >= 0) { @try { [g setValue:@(gStyle) forKey:@"style"]; } @catch (NSException *e) { LF(@"style ex %@", [e reason]); } }\n'
       '    if (variant >= 0) { @try { [g setValue:@(variant) forKey:@"_variant"]; }')
assert old in src
src = src.replace(old, new)
old2 = '  pump(0.8);\n  LF(@"SCENE %@ variant=%ld multi=%d'
new2 = '  pump(0.8);\n  LF(@"STYLE %@ style=%@ variant=%@", tag, D(KV([views objectAtIndex:0], @"style")), D(KV([views objectAtIndex:0], @"_variant")));\n  LF(@"SCENE %@ variant=%ld multi=%d'
assert old2 in src
src = src.replace(old2, new2)
NEW_MAIN = r'''  // ===== run 7 =====
  gLight = 1;
  { double sz[4][2] = {{64, 64}, {164, 164}, {600, 72}, {600, 260}};
    for (int st = 0; st <= 1; st++) for (int i = 0; i < 4; i++) {
      double w = sz[i][0], h = sz[i][1], H = h > 180 ? 440 : 200;
      CGRect one[] = { CGRectMake(w < 600 ? 100 : 50, floor((H - h) / 2), w, h) };
      double r1[] = { MIN(0.225 * MIN(w, h), MIN(w, h) / 2) };
      gStyle = st;
      sceneMulti([NSString stringWithFormat:@"pub%d_%gx%g", st, w, h], pat1, CGSizeMake(700, H), one, r1, 1, -1, 1);
    } }
  setDark(1);
  { CGRect one[] = { CGRectMake(50, 64, 600, 72) }; double r1[] = { 16.2 };
    gStyle = 1; sceneMulti(@"pubd1_600x72", pat1, CGSizeMake(700, 200), one, r1, 1, -1, 1);
    gStyle = 0; sceneMulti(@"pubd0_600x72", pat1, CGSizeMake(700, 200), one, r1, 1, -1, 1); }
  setDark(0);
  gStyle = -1;
  gLight = 0;
  LF(@"DONE");
  return 0;
} }
'''
i = src.index("MAIN = r'''")
j = src.index("'''", i + len("MAIN = r'''")) + 3
src = src[:i] + 'MAIN = r' + "'''" + NEW_MAIN + "'''" + src[j:]
exec(compile(src, 'patch5_run7', 'exec'))
