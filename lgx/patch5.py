# Run 5: edits lgx/capture.m on the runner before compiling.
# Adds: light logging modes, highlight resource dumps (gamma LUT, asg77 weights, noise texture),
# function-constant value logging, region backdrops of the Tahoe Day frame, multi-shape scenes,
# Control Center geometry for every variant, and uniform sweeps (light + dark).
import sys, re
p = sys.argv[1]
s = open(p).read()
log = []
def rep(old, new):
    global s
    if old not in s:
        log.append('MISSING ' + old[:70].replace('\n', ' ')); return False
    s = s.replace(old, new, 1); log.append('ok ' + old[:50].replace('\n', ' ')); return True

rep('static volatile int gOn = 0;', 'static volatile int gOn = 0;\nstatic int gLight = 0;')
# buffer dumps: 4096 B normally, 512 B in light modes
rep('m = full ? MIN(n, (NSUInteger)1024) : MIN(n, (NSUInteger)96);', 'm = full ? MIN(n, (NSUInteger)(gLight ? 512 : 4096)) : MIN(n, (NSUInteger)96);')

RES = r'''
static NSMutableSet *gDumped;
static void lgxRes(ES *s, NSString *pn, int d) {
  if ([pn rangeOfString:@"A2X"].location == NSNotFound) return;
  if (!gDumped) gDumped = [NSMutableSet new];
  for (NSNumber *k in [s->fb allKeys]) {
    id v = [s->fb objectForKey:k];
    if (![v isKindOfClass:[NSArray class]]) continue;
    id<MTLBuffer> b = [v objectAtIndex:0]; NSUInteger off = [[v objectAtIndex:1] unsignedIntegerValue];
    NSString *lb = [b label] ? [b label] : @"-";
    if ([lb rangeOfString:@"gamma"].location == NSNotFound && [lb rangeOfString:@"asg"].location == NSNotFound) continue;
    NSString *key = [NSString stringWithFormat:@"%@@%lu", lb, (unsigned long)off];
    if ([gDumped containsObject:key]) continue;
    [gDumped addObject:key];
    if ([b storageMode] == MTLStorageModePrivate || ![b contents] || off >= [b length]) { LF(@"BUFDUMP skip %@", key); continue; }
    NSUInteger n = [b length] - off;
    NSString *nm = [[lb stringByReplacingOccurrencesOfString:@"." withString:@"_"] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSString *path = [NSString stringWithFormat:@"%@/tex/buf_%@_%@_d%d_FB%@_off%lu_len%lu.bin", gDir, nm, gTag, d, k, (unsigned long)off, (unsigned long)n];
    [[NSData dataWithBytes:(const char *)[b contents] + off length:n] writeToFile:path atomically:NO];
    LF(@"BUFDUMP %@ d%d FB%@ %@ off%lu len%lu", gTag, d, k, lb, (unsigned long)off, (unsigned long)n);
  }
  for (NSNumber *k in [s->ft allKeys]) {
    id<MTLTexture> t = [s->ft objectForKey:k];
    NSString *lb = [t label] ? [t label] : @"-";
    if ([lb rangeOfString:@"noise"].location == NSNotFound) continue;
    NSString *key = [NSString stringWithFormat:@"tex%p", t];
    if ([gDumped containsObject:key]) continue;
    [gDumped addObject:key];
    addRead(t, [NSString stringWithFormat:@"%@_d%d_ft%@_noise", gTag, d, k]);
    LF(@"NOISE %@ d%d FT%@ %@", gTag, d, k, TD(t));
  }
}
'''
rep('static void logDraw(id enc, NSString *what) {', RES + 'static void logDraw(id enc, NSString *what) {')
rep('''  int d = gDraw++;
  NSMutableString *m = ''', '''  int d = gDraw++;
  if (gLight >= 2 && !glass) { LF(@"DRAW %@ d%d e%d %@ pso=%p %@ | light", gTag, d, s->idx, what, s->pso, pn); return; }
  NSMutableString *m = ''')
rep('''  if (glass) {
    for (NSNumber *k in [s->ft allKeys])''', '''  if (!gLight) lgxRes(s, pn, d);
  if (glass && !gLight) {
    for (NSNumber *k in [s->ft allKeys])''')
rep('  readTex(tex, [tag stringByAppendingString:@"_out"], NO);', '  if (gLight < 2) readTex(tex, [tag stringByAppendingString:@"_out"], NO);')

# region of the aspect-filled screen (top-left origin, pixels)
REG = r'''
static CGImageRef tahoeRegion(CGImageRef img, int screenW, int screenH, int rx, int ry, int rw, int rh) {
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef c = CGBitmapContextCreate(NULL, rw, rh, 8, rw * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
  double iw = CGImageGetWidth(img), ih = CGImageGetHeight(img), sc = fmax(screenW / iw, screenH / ih);
  double dw = iw * sc, dh = ih * sc;
  CGContextDrawImage(c, CGRectMake((screenW - dw) / 2 - rx, (screenH - dh) / 2 - (screenH - ry - rh), dw, dh), img);
  CGImageRef out = CGBitmapContextCreateImage(c); CGContextRelease(c); CGColorSpaceRelease(cs);
  LF(@"REGION %d,%d %dx%d of %dx%d scale %.6f", rx, ry, rw, rh, screenW, screenH, sc);
  return out;
}
'''
rep('static void renderFrame(CALayer *root', REG + '\nstatic void renderFrame(CALayer *root')


# --- run-4 pieces: async compute pipelines, library function records, layer/filter properties ---
EXTRA_DEV = r'''
  hk(c, "newComputePipelineStateWithDescriptor:options:completionHandler:", ^id(IMP o, SEL s) { return BLK(^void(id self, id d, NSUInteger op, id h) {
    NSString *desc = [[NSString stringWithFormat:@"compute %@", [[d computeFunction] name]] retain]; void (^hh)(id, id, NSError *) = h;
    void (^w)(id, id, NSError *) = ^(id p, id r, NSError *e) { notePipe(p, desc, "cdasync"); if (hh) hh(p, r, e); };
    ((Fv_onh)o)(self, s, d, op, [[w copy] autorelease]); }); });
  hk(c, "newComputePipelineStateWithFunction:options:completionHandler:", ^id(IMP o, SEL s) { return BLK(^void(id self, id f, NSUInteger op, id h) {
    NSString *desc = [[NSString stringWithFormat:@"compute %@", [f name]] retain]; void (^hh)(id, id, NSError *) = h;
    void (^w)(id, id, NSError *) = ^(id p, id r, NSError *e) { notePipe(p, desc, "cfasync"); if (hh) hh(p, r, e); };
    ((Fv_onh)o)(self, s, f, op, [[w copy] autorelease]); }); });
}
'''
rep('''    ((Fv_oh)o)(self, s, f, [[w copy] autorelease]); }); });
}
''', '''    ((Fv_oh)o)(self, s, f, [[w copy] autorelease]); }); });''' + EXTRA_DEV)
LIB = r'''
typedef id (*LgxF1)(id, SEL, id);
typedef id (*LgxF2)(id, SEL, id, NSError **);
typedef id (*LgxF3)(id, SEL, id, id, NSError **);
static void lgxLibClass(Class c) {
  LF(@"LIBCLASS %s", class_getName(c));
  hk(c, "newFunctionWithName:", ^id(IMP o, SEL s) { return BLK(^id(id self, id n) { id f = ((LgxF1)o)(self, s, n); LF(@"FUNC name=%@ f=%p lib=%p", n, f, self); return f; }); });
  hk(c, "newFunctionWithName:constantValues:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id n, id cv, NSError **er) { id f = ((LgxF3)o)(self, s, n, cv, er); LF(@"FUNCCV name=%@ f=%p fname=%@ cv=%@", n, f, [f name], [cv debugDescription]); return f; }); });
  hk(c, "newFunctionWithDescriptor:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d, NSError **er) { id f = ((LgxF2)o)(self, s, d, er);
    NSString *sn = nil; @try { sn = [d valueForKey:@"specializedName"]; } @catch (NSException *e) {}
    LF(@"FUNCD name=%@ spec=%@ f=%p fname=%@ cv=%@", [d name], sn, f, [f name], [[d constantValues] debugDescription]); return f; }); });
}
static void lgxLib(void) {
  NSError *er = nil;
  id lib = [gDev newLibraryWithSource:@"#include <metal_stdlib>\nkernel void lgx_k(){}\n" options:nil error:&er];
  if (lib) lgxLibClass(object_getClass(lib)); else LF(@"LIB probe failed %@", er);
  for (NSString *cn in @[@"_MTLLibrary", @"MTLLibrary", @"AppleParavirtLibrary", @"MTLDebugLibrary"]) { Class c = NSClassFromString(cn); if (c) lgxLibClass(c); }
}
static int gNoHL = 0;
static void lgxProps(id o, NSString *tag) {
  if (!o) return;
  for (Class c = object_getClass(o); c && c != [NSObject class]; c = class_getSuperclass(c)) {
    unsigned n = 0; objc_property_t *ps = class_copyPropertyList(c, &n);
    for (unsigned i = 0; i < n; i++) {
      NSString *pn = [NSString stringWithUTF8String:property_getName(ps[i])];
      const char *at = property_getAttributes(ps[i]);
      if (at && (at[1] == '^' || at[1] == '*' || at[1] == '?' || at[1] == 'r')) continue;
      NSString *v = @"<ex>";
      @try { id x = [o valueForKey:pn]; v = x ? [[x description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"nil"; } @catch (NSException *e) {}
      if ([v length] > 300) v = [v substringToIndex:300];
      LF(@"PROP %@ %s.%@ = %@", tag, class_getName(c), pn, v);
    }
    free(ps);
  }
}
static void lgxLayerInfo(CALayer *l, NSString *path) {
  id eff = nil; @try { eff = [l valueForKey:@"effect"]; } @catch (NSException *e) {}
  if (eff) lgxProps(eff, [path stringByAppendingString:@".effect"]);
  int k = 0;
  for (id f in [l filters]) {
    NSString *t = [NSString stringWithFormat:@"%@.filter%d", path, k++];
    lgxProps(f, t);
    for (NSString *key in @[@"inputColorMatrix", @"inputAmount", @"inputRadius", @"inputScale", @"inputBias"]) {
      @try { id x = [f valueForKey:key]; if (x) LF(@"FVAL %@ %@ = %@", t, key, x); } @catch (NSException *e) {}
    }
  }
  if (gNoHL && eff && [NSStringFromClass([eff class]) rangeOfString:@"Highlight"].location != NSNotFound) { [l setHidden:YES]; LF(@"NOHL hid %@ %@", path, NSStringFromClass([eff class])); }
  int i = 0;
  for (CALayer *s in [l sublayers]) lgxLayerInfo(s, [NSString stringWithFormat:@"%@.%d", path, i++]);
}
'''
FCV = r'''
typedef void (*LgxSetIdx)(id, SEL, const void *, NSUInteger, NSUInteger);
typedef void (*LgxSetNm)(id, SEL, const void *, NSUInteger, id);
typedef void (*LgxSetRg)(id, SEL, const void *, NSUInteger, NSRange);
static NSUInteger lgxDT(NSUInteger t) {
  if (t >= 53 && t <= 56) return t - 52;
  if (t >= 45 && t <= 52) return ((t - 45) % 4) + 1;
  if (t >= 37 && t <= 44) return 2 * (((t - 37) % 4) + 1);
  if (t >= 16 && t <= 19) return 2 * (t - 15);
  if (t >= 29 && t <= 36) return 4 * (((t - 29) % 4) + 1);
  if (t >= 3 && t <= 6) return 4 * (t - 2);
  return 4;
}
static void lgxFCV(void) {
  id cv0 = [[MTLFunctionConstantValues alloc] init];
  Class c = object_getClass(cv0);
  LF(@"FCVCLASS %s super=%s", class_getName(c), class_getName(class_getSuperclass(c)));
  hk(c, "setConstantValue:type:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, const void *v, NSUInteger t, NSUInteger i) { if (v) LF(@"FCV cv=%p idx=%lu type=%lu val=%@", self, (unsigned long)i, (unsigned long)t, HX(v, lgxDT(t))); ((LgxSetIdx)o)(self, s, v, t, i); }); });
  hk(c, "setConstantValue:type:withName:", ^id(IMP o, SEL s) { return BLK(^void(id self, const void *v, NSUInteger t, id n) { if (v) LF(@"FCV cv=%p name=%@ type=%lu val=%@", self, n, (unsigned long)t, HX(v, lgxDT(t))); ((LgxSetNm)o)(self, s, v, t, n); }); });
  hk(c, "setConstantValues:type:withRange:", ^id(IMP o, SEL s) { return BLK(^void(id self, const void *v, NSUInteger t, NSRange r) { if (v) LF(@"FCV cv=%p range=%lu+%lu type=%lu val=%@", self, (unsigned long)r.location, (unsigned long)r.length, (unsigned long)t, HX(v, lgxDT(t) * r.length)); ((LgxSetRg)o)(self, s, v, t, r); }); });
  [cv0 release];
}
static void setDark(int dk) { [gWin setAppearance:[NSAppearance appearanceNamed:dk ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]]; pump(0.3); LF(@"APPEARANCE %@", dk ? @"dark" : @"light"); }
static BOOL sceneMulti(NSString *tag, CGImageRef bg, CGSize ptSize, const CGRect *gfs, const double *radii, int n, long variant, double scale) {
  Class G = NSClassFromString(@"NSGlassEffectView");
  if (!G) { LF(@"no NSGlassEffectView"); return NO; }
  NSMutableArray *views = [NSMutableArray array];
  for (int i = 0; i < n; i++) {
    NSView *g = [[[G alloc] initWithFrame:NSMakeRect(10 + 160 * i, 20, gfs[i].size.width, gfs[i].size.height)] autorelease];
    @try { [g setValue:@(radii[i]) forKey:@"cornerRadius"]; } @catch (NSException *e) { LF(@"cornerRadius ex %@", [e reason]); }
    if (variant >= 0) { @try { [g setValue:@(variant) forKey:@"_variant"]; } @catch (NSException *e) { LF(@"variant ex %@", [e reason]); } }
    [gHost addSubview:g]; [views addObject:g];
  }
  pump(0.8);
  LF(@"SCENE %@ variant=%ld multi=%d readback=%@ pts=%gx%g scale=%g appearance=%@", tag, variant, n, D(KV([views objectAtIndex:0], @"_variant")), ptSize.width, ptSize.height, scale, [[[views objectAtIndex:0] effectiveAppearance] name]);
  for (int i = 0; i < n; i++) LF(@"SHAPE %@ %d radius=%g glass=%@", tag, i, radii[i], NSStringFromRect(NSRectFromCGRect(gfs[i])));
  CALayer *root = [CALayer layer];
  [root setAnchorPoint:CGPointZero]; [root setBounds:CGRectMake(0, 0, ptSize.width * scale, ptSize.height * scale)]; [root setPosition:CGPointZero];
  CALayer *cont = [CALayer layer];
  [cont setAnchorPoint:CGPointZero]; [cont setBounds:CGRectMake(0, 0, ptSize.width, ptSize.height)]; [cont setPosition:CGPointZero];
  [cont setTransform:CATransform3DMakeScale(scale, scale, 1)];
  [root addSublayer:cont];
  CALayer *bgl = [CALayer layer];
  [bgl setAnchorPoint:CGPointZero]; [bgl setFrame:CGRectMake(0, 0, ptSize.width, ptSize.height)];
  [bgl setContents:(id)bg]; [bgl setContentsGravity:kCAGravityResize]; [bgl setContentsScale:scale];
  [bgl setMagnificationFilter:kCAFilterNearest]; [bgl setMinificationFilter:kCAFilterNearest];
  [cont addSublayer:bgl];
  NSMutableArray *glasses = [NSMutableArray array];
  for (int i = 0; i < n; i++) {
    NSView *g = [views objectAtIndex:i]; CALayer *gl = [g layer];
    if (i == 0 && gLight < 2) { walk(gl, @"g", 0); lgxLayerInfo(gl, @"g"); }
    [gl retain]; [gl removeFromSuperlayer]; CALayer *glass = [gl autorelease];
    [glass setFrame:gfs[i]]; setScaleRec(glass, scale); [cont addSublayer:glass]; [glasses addObject:glass];
  }
  [CATransaction flush];
  for (int i = 0; i < n; i++) [[glasses objectAtIndex:i] setFrame:gfs[i]];
  renderFrame(root, (int)lround(ptSize.width * scale), (int)lround(ptSize.height * scale), tag);
  for (CALayer *gq in glasses) [gq removeFromSuperlayer];
  for (NSView *v in views) [v removeFromSuperview];
  pump(0.1);
  return YES;
}
'''
rep('static BOOL scene(NSString *tag, CGImageRef bg,', LIB + FCV + '\nstatic BOOL scene(NSString *tag, CGImageRef bg,')
rep('  walk(gl, @"g", 0);\n', '  if (gLight < 2) { walk(gl, @"g", 0);\n  lgxLayerInfo(gl, @"g"); }\n')
rep('  hookDevice(object_getClass(gDev));\n', '  hookDevice(object_getClass(gDev));\n  lgxLib();\n  lgxFCV();\n')
# --- replace the scene list in main ---
MAIN = r'''  // ===== run 5 =====
  gLight = 0;
  scene(@"p1_v0", pat1, CGSizeMake(700, 200), gfp, 24, 0, 1, strategy);
  gTahoe = tahoeFrame(0, 0);
  if (gTahoe) {
    CGImageRef full0 = tahoeRegion(gTahoe, 2880, 1800, 0, 0, 2880, 1800);
    writeCG([gDir stringByAppendingPathComponent:@"img/wall_t0_2880x1800.png"], full0);
    CGImageRelease(full0);
  }
  // Control Center region (screen px x 2240..2880, y 120..1040 = pt origin 1120,60 size 320x460)
  { CGImageRef f = tahoeFrame(22.5, 0);
    if (f) {
      CGImageRef reg = tahoeRegion(f, 2880, 1800, 2240, 120, 640, 920);
      writeCG([gDir stringByAppendingPathComponent:@"img/cc_bg_t22.5.png"], reg);
      CGRect sh[] = { CGRectMake(14, 82, 292, 64), CGRectMake(14, 6, 292, 64), CGRectMake(166, 234, 64, 64), CGRectMake(166, 158, 140, 64),
                      CGRectMake(14, 234, 140, 64), CGRectMake(14, 158, 64, 64), CGRectMake(166, 310, 140, 140), CGRectMake(14, 386, 140, 64) };
      double rr[] = {24, 24, 32, 32, 32, 32, 32, 32};
      gLight = 1;
      long order[] = {0, 3, 2, 20, 6, 11, 5, 9, 15, 1, 4, 7, 8, 10, 12, 13, 14, 16, 17, 18, 19};
      for (int i = 0; i < 21; i++) sceneMulti([NSString stringWithFormat:@"cc_v%ld", order[i]], reg, CGSizeMake(320, 460), sh, rr, 8, order[i], 2);
      double rs[] = {12, 14, 16, 18, 20, 28};
      for (int i = 0; i < 6; i++) { CGRect one[] = { sh[0] }; double r1[] = { rs[i] }; sceneMulti([NSString stringWithFormat:@"ccr%g_v0", rs[i]], reg, CGSizeMake(320, 460), one, r1, 1, 0, 2); }
      CGImageRelease(reg); CGImageRelease(f);
    } }
  // wallpaper frames for time matching of the Control Center screenshot (same region)
  for (int k = 0; k <= 16; k++) { double t = 19 + 0.5 * k; if (t == 22.5) continue; CGImageRef f = tahoeFrame(t, 0);
    if (f) { CGImageRef reg = tahoeRegion(f, 2880, 1800, 2240, 120, 640, 920); writeCG([gDir stringByAppendingPathComponent:[NSString stringWithFormat:@"img/cc_bg_t%.1f.png", t]], reg); CGImageRelease(reg); CGImageRelease(f); } }
  // uniform sweeps (no readbacks)
  gLight = 2;
  { double hs[] = {20, 28, 36, 44, 52, 64, 72, 100, 140, 200};
    long order[] = {3, 0, 2, 20, 6, 11, 5, 9, 15, 1, 4, 7, 8, 10, 12, 13, 14, 16, 17, 18, 19};
    for (int j = 0; j < 21; j++) for (int i = 0; i < 10; i++) { double H = hs[i]; long v = order[j];
      scene([NSString stringWithFormat:@"sw_h%g_v%ld", H, v], pat1, CGSizeMake(700, 240), CGRectMake(50, floor((240 - H) / 2), 600, H), MIN(24.0, H / 2), v, 1, strategy); }
    double ws[] = {64, 100, 300};
    for (int i = 0; i < 3; i++) scene([NSString stringWithFormat:@"sww%g_h64_v3", ws[i]], pat1, CGSizeMake(700, 240), CGRectMake(50, 88, ws[i], 64), 24, 3, 1, strategy);
    setDark(1);
    double hd[] = {28, 64, 140};
    for (int j = 0; j < 21; j++) for (int i = 0; i < 3; i++) { double H = hd[i]; long v = order[j];
      scene([NSString stringWithFormat:@"swd_h%g_v%ld", H, v], pat1, CGSizeMake(700, 240), CGRectMake(50, floor((240 - H) / 2), 600, H), MIN(24.0, H / 2), v, 1, strategy); }
    setDark(0); }
  // dark Dock frames over the real strip
  if (gTahoe) {
    CGImageRef strip = tahoeStrip(gTahoe, 2880, 1800, 200);
    CGRect dock = CGRectMake(48, 5.5, 1343.5, 78);
    gLight = 1; setDark(1);
    long dv[] = {3, 0, 2};
    for (int i = 0; i < 3; i++) scene([NSString stringWithFormat:@"dockdark_v%ld", dv[i]], strip, CGSizeMake(1440, 100), dock, 24, dv[i], 2, strategy);
    setDark(0); CGImageRelease(strip);
  }
  gLight = 0;
  LF(@"DONE");
  return 0;
} }
'''
a = s.find('  long pv[] = {0, 2, 3, 4, 5, 6, 9, 11, 15};')
b = s.find('  LF(@"DONE");\n  return 0;\n} }')
if a < 0 or b < 0: log.append('MISSING main block')
else:
    s = s[:a] + MAIN + s[b + len('  LF(@"DONE");\n  return 0;\n} }'):]; log.append('ok main block')
open(p, 'w').write(s)
print('\n'.join(log))
bad = [l for l in log if l.startswith('MISSING')]
print('patch result:', 'FAIL' if bad else 'OK', len(log))
