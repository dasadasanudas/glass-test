# Edits lgx/capture.m on the runner before compiling (keeps the big file untouched in the repo).
import sys
p = sys.argv[1]
s = open(p).read()
log = []
def rep(old, new):
    global s
    if old not in s:
        log.append('MISSING ' + old[:70].replace('\n', ' ')); return False
    s = s.replace(old, new, 1); log.append('ok ' + old[:50].replace('\n', ' ')); return True

# 1. dump up to 4096 bytes per bound buffer (full vertex ranges)
rep('m = full ? MIN(n, (NSUInteger)1024) : MIN(n, (NSUInteger)96);', 'm = full ? MIN(n, (NSUInteger)4096) : MIN(n, (NSUInteger)96);')

# 2. two more compute pipeline creation paths + library function creation records
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
rep('static BOOL scene(NSString *tag, CGImageRef bg,', LIB + '\nstatic BOOL scene(NSString *tag, CGImageRef bg,')
rep('  walk(gl, @"g", 0);\n', '  walk(gl, @"g", 0);\n  lgxLayerInfo(gl, @"g");\n')
rep('  hookDevice(object_getClass(gDev));\n', '  hookDevice(object_getClass(gDev));\n  lgxLib();\n')

# 3. extra scenes: height sweep, width sweep, no-highlight references
SC = r'''
  { double hs[] = {20, 28, 36, 44, 52, 60, 68, 84, 100, 120, 140, 160, 180, 190};
    for (int i = 0; i < (int)(sizeof hs / sizeof hs[0]); i++) { double H = hs[i];
      scene([NSString stringWithFormat:@"h%g_v0", H], pat1, CGSizeMake(700, 200), CGRectMake(50, floor((200 - H) / 2), 600, H), MIN(16.0, H / 2), 0, 1, strategy); } }
  { double ws[] = {60, 100, 200, 400};
    for (int i = 0; i < 4; i++) scene([NSString stringWithFormat:@"w%g_v0", ws[i]], pat1, CGSizeMake(700, 200), CGRectMake(50, 64, ws[i], 72), 24, 0, 1, strategy); }
  scene(@"h72_v2", pat1, CGSizeMake(700, 200), gfp, 24, 2, 1, strategy);
  scene(@"h160_v2", pat1, CGSizeMake(700, 200), CGRectMake(50, 20, 600, 160), 16, 2, 1, strategy);
  gNoHL = 1;
  scene(@"p1_v0_nohl", pat1, CGSizeMake(700, 200), gfp, 24, 0, 1, strategy);
  scene(@"p1_v2_nohl", pat1, CGSizeMake(700, 200), gfp, 24, 2, 1, strategy);
  gNoHL = 0;
'''
rep('  // Real wallpaper: Tahoe Day frame', SC + '  // Real wallpaper: Tahoe Day frame')
rep('''    for (long v = 0; v <= 20; v++) scene([NSString stringWithFormat:@"dock_v%ld", v], strip, CGSizeMake(1440, 100), dock, 24, v, 2, strategy);
''', '''    for (long v = 0; v <= 20; v++) scene([NSString stringWithFormat:@"dock_v%ld", v], strip, CGSizeMake(1440, 100), dock, 24, v, 2, strategy);
    gNoHL = 1;
    scene(@"dock_v0_nohl", strip, CGSizeMake(1440, 100), dock, 24, 0, 2, strategy);
    scene(@"dock_v2_nohl", strip, CGSizeMake(1440, 100), dock, 24, 2, 2, strategy);
    gNoHL = 0;
''')
open(p, 'w').write(s)
print('\n'.join(log))
bad = [l for l in log if l.startswith('MISSING')]
print('patch result:', 'FAIL' if bad else 'OK', len(log))
