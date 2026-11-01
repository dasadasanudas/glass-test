// LGX v1 ground-truth capture (Nov 1, from scratch).
// Renders real NSGlassEffectView layer trees with Apple's own CARenderer, in-process, and
// records the Metal work CoreAnimation issues: pipeline function names and blend state,
// every draw's uniform bytes, bound textures and render targets. Reads back the textures
// the glass shader samples (all mip levels) and the final frames.
// Built with -fno-objc-arc on purpose: hooks pass +1 (new*) results through untouched.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import <time.h>
#import <unistd.h>

static FILE *gL;
static NSString *gDir;
static volatile int gOn = 0;
static int gDraw = 0, gEncCount = 0;
static __thread int gDepth = 0;
static NSMutableDictionary *gPipe, *gEnc;
static NSMutableArray *gRead;
static NSMutableSet *gHooked, *gHookedCls;
static NSString *gTag = @"-";
static id<MTLDevice> gDev;
static id<MTLCommandQueue> gQ;
static CGColorSpaceRef gCS;

static void LS(NSString *s) { if (!s) s = @"<nil>"; const char *u = [s UTF8String]; fputs(u ? u : "<utf8>", gL); fputc('\n', gL); fflush(gL); }
#define LF(...) LS([NSString stringWithFormat:__VA_ARGS__])
static double nowS(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static void pump(double s) {
  NSDate *e = [NSDate dateWithTimeIntervalSinceNow:s];
  while ([e timeIntervalSinceNow] > 0) {
    NSEvent *n = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02] inMode:NSDefaultRunLoopMode dequeue:YES];
    if (n) [NSApp sendEvent:n];
  }
}
static NSString *HX(const void *p, NSUInteger n) {
  static const char *dg = "0123456789abcdef";
  NSMutableData *m = [NSMutableData dataWithLength:n * 2];
  char *o = (char *)[m mutableBytes]; const unsigned char *b = (const unsigned char *)p;
  for (NSUInteger i = 0; i < n; i++) { o[2 * i] = dg[b[i] >> 4]; o[2 * i + 1] = dg[b[i] & 15]; }
  return [[[NSString alloc] initWithData:m encoding:NSASCIIStringEncoding] autorelease];
}
static NSString *TD(id<MTLTexture> t) {
  if (!t) return @"nil";
  NSString *par = @"";
  @try { if ([t parentTexture]) par = [NSString stringWithFormat:@" parent=%p plvl=%lu", [t parentTexture], (unsigned long)[t parentRelativeLevel]]; } @catch (NSException *e) {}
  return [NSString stringWithFormat:@"T%p[%lux%lu f%lu m%lu ty%lu st%lu u%lu fbo%d lbl=%@%@]", t, (unsigned long)[t width], (unsigned long)[t height], (unsigned long)[t pixelFormat], (unsigned long)[t mipmapLevelCount], (unsigned long)[t textureType], (unsigned long)[t storageMode], (unsigned long)[t usage], (int)[t isFramebufferOnly], [t label] ? [t label] : @"-", par];
}

@interface ES : NSObject { @public void *pso; int idx; NSMutableDictionary *fb, *vb, *ft, *vt; NSString *vp, *sc, *rt; id rtTex; } @end
@implementation ES @end
static ES *esFor(id enc) {
  NSNumber *k = @((uintptr_t)enc); ES *s = [gEnc objectForKey:k];
  if (!s) {
    s = [[ES alloc] init];
    s->fb = [NSMutableDictionary new]; s->vb = [NSMutableDictionary new]; s->ft = [NSMutableDictionary new]; s->vt = [NSMutableDictionary new];
    s->vp = @"-"; s->sc = @"-"; s->rt = @"?"; s->rtTex = nil; s->pso = NULL; s->idx = gEncCount++;
    [gEnc setObject:s forKey:k]; [s release];
  }
  return s;
}
static NSString *bufStr(id v, BOOL full) {
  if ([v isKindOfClass:[NSData class]]) {
    NSData *d = v; NSUInteger n = [d length], m = full ? MIN(n, (NSUInteger)2048) : MIN(n, (NSUInteger)96);
    return [NSString stringWithFormat:@"bytes[%lu]:%@%@", (unsigned long)n, HX([d bytes], m), m < n ? @".." : @""];
  }
  NSArray *a = v; id<MTLBuffer> b = [a objectAtIndex:0]; NSUInteger off = [[a objectAtIndex:1] unsignedIntegerValue];
  NSString *h = @"";
  @try {
    if ([b storageMode] != MTLStorageModePrivate && [b contents] && off < [b length]) {
      NSUInteger n = [b length] - off, m = full ? MIN(n, (NSUInteger)1024) : MIN(n, (NSUInteger)96);
      h = [NSString stringWithFormat:@":%@%@", HX((const char *)[b contents] + off, m), m < n ? @".." : @""];
    }
  } @catch (NSException *e) { h = @":<ex>"; }
  return [NSString stringWithFormat:@"buf%p[len%lu off%lu st%lu lbl=%@]%@", b, (unsigned long)[b length], (unsigned long)off, (unsigned long)[b storageMode], [b label] ? [b label] : @"-", h];
}
static void addRead(id t, NSString *tag) {
  if (!t) return;
  for (NSArray *r in gRead) if ([r objectAtIndex:0] == t) return;
  [gRead addObject:@[t, tag]];
}
static NSString *pipeName(void *p) { if (!p) return @"?"; NSString *n; @synchronized (gPipe) { n = [[[gPipe objectForKey:@((uintptr_t)p)] retain] autorelease]; } return n ? n : @"?"; }
static void appendState(NSMutableString *m, ES *s, BOOL full) {
  NSArray *ks;
  ks = [[s->fb allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber *k in ks) [m appendFormat:@"\n   FB%@ %@", k, bufStr([s->fb objectForKey:k], full)];
  ks = [[s->vb allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber *k in ks) [m appendFormat:@"\n   VB%@ %@", k, bufStr([s->vb objectForKey:k], full)];
  ks = [[s->ft allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber *k in ks) [m appendFormat:@"\n   FT%@ %@", k, TD([s->ft objectForKey:k])];
  ks = [[s->vt allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber *k in ks) [m appendFormat:@"\n   VT%@ %@", k, TD([s->vt objectForKey:k])];
}
static void logDraw(id enc, NSString *what) {
  ES *s = esFor(enc);
  NSString *pn = pipeName(s->pso);
  BOOL glass = [pn rangeOfString:@"glass"].location != NSNotFound;
  int d = gDraw++;
  NSMutableString *m = [NSMutableString stringWithFormat:@"DRAW %@ d%d e%d %@ pso=%p %@ | rt=%@ vp=%@ sc=%@", gTag, d, s->idx, what, s->pso, pn, s->rt, s->vp, s->sc];
  appendState(m, s, YES);
  LS(m);
  if (glass) {
    for (NSNumber *k in [s->ft allKeys]) addRead([s->ft objectForKey:k], [NSString stringWithFormat:@"%@_d%d_ft%@", gTag, d, k]);
    if (s->rtTex) addRead(s->rtTex, [NSString stringWithFormat:@"%@_d%d_rt", gTag, d]);
  }
}

typedef id (^Factory)(IMP o, SEL s);
static void hk(Class cls, const char *name, Factory f) {
  if (!cls) return;
  SEL sel = sel_registerName(name);
  Method m = class_getInstanceMethod(cls, sel);
  if (!m) { LF(@"  nohook %s -%s", class_getName(cls), name); return; }
  NSValue *key = [NSValue valueWithPointer:m];
  if ([gHooked containsObject:key]) return;
  [gHooked addObject:key];
  IMP o = method_getImplementation(m);
  method_setImplementation(m, imp_implementationWithBlock(f(o, sel)));
  LF(@"  hooked %s -%s", class_getName(cls), name);
}
#define BLK(...) [[(__VA_ARGS__) copy] autorelease]
#define PRE gDepth++; if (gDepth == 1)
#define POST gDepth--;

typedef void (*Fv)(id, SEL);
typedef void (*Fv_o)(id, SEL, id);
typedef void (*Fv_pnn)(id, SEL, const void *, NSUInteger, NSUInteger);
typedef void (*Fv_onn)(id, SEL, id, NSUInteger, NSUInteger);
typedef void (*Fv_nn)(id, SEL, NSUInteger, NSUInteger);
typedef void (*Fv_on)(id, SEL, id, NSUInteger);
typedef void (*Fv_bufs)(id, SEL, const id *, const NSUInteger *, NSRange);
typedef void (*Fv_texs)(id, SEL, const id *, NSRange);
typedef void (*Fv_vp)(id, SEL, MTLViewport);
typedef void (*Fv_sc)(id, SEL, MTLScissorRect);
typedef void (*Fv_n3)(id, SEL, NSUInteger, NSUInteger, NSUInteger);
typedef void (*Fv_n4)(id, SEL, NSUInteger, NSUInteger, NSUInteger, NSUInteger);
typedef void (*Fv_n5)(id, SEL, NSUInteger, NSUInteger, NSUInteger, NSUInteger, NSUInteger);
typedef void (*Fv_di)(id, SEL, NSUInteger, NSUInteger, NSUInteger, id, NSUInteger);
typedef void (*Fv_di6)(id, SEL, NSUInteger, NSUInteger, NSUInteger, id, NSUInteger, NSUInteger);
typedef void (*Fv_di8)(id, SEL, NSUInteger, NSUInteger, NSUInteger, id, NSUInteger, NSUInteger, NSInteger, NSUInteger);
typedef void (*Fv_ss)(id, SEL, MTLSize, MTLSize);
typedef void (*Fv_ctt)(id, SEL, id, NSUInteger, NSUInteger, MTLOrigin, MTLSize, id, NSUInteger, NSUInteger, MTLOrigin);
typedef void (*Fv_oo)(id, SEL, id, id);
typedef void (*Fv_ctl)(id, SEL, id, NSUInteger, NSUInteger, id, NSUInteger, NSUInteger, NSUInteger, NSUInteger);
typedef id (*Fo)(id, SEL);
typedef id (*Fo_o)(id, SEL, id);
typedef id (*Fo_n)(id, SEL, NSUInteger);
typedef id (*Fo_oe)(id, SEL, id, NSError **);
typedef id (*Fo_onre)(id, SEL, id, NSUInteger, id *, NSError **);
typedef void (*Fv_oh)(id, SEL, id, id);
typedef void (*Fv_onh)(id, SEL, id, NSUInteger, id);

static void hookRender(Class c) {
  if (!c || [gHookedCls containsObject:NSStringFromClass(c)]) return;
  [gHookedCls addObject:NSStringFromClass(c)];
  LF(@"HOOK render encoder class %s", class_getName(c));
  hk(c, "setRenderPipelineState:", ^id(IMP o, SEL s) { return BLK(^void(id self, id p) { PRE { esFor(self)->pso = (void *)p; } ((Fv_o)o)(self, s, p); POST }); });
  hk(c, "setFragmentBytes:length:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, const void *b, NSUInteger n, NSUInteger i) { PRE { if (b) [esFor(self)->fb setObject:[NSData dataWithBytes:b length:n] forKey:@(i)]; } ((Fv_pnn)o)(self, s, b, n, i); POST }); });
  hk(c, "setVertexBytes:length:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, const void *b, NSUInteger n, NSUInteger i) { PRE { if (b) [esFor(self)->vb setObject:[NSData dataWithBytes:b length:n] forKey:@(i)]; } ((Fv_pnn)o)(self, s, b, n, i); POST }); });
  hk(c, "setFragmentBuffer:offset:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, id b, NSUInteger off, NSUInteger i) { PRE { if (b) [esFor(self)->fb setObject:@[b, @(off)] forKey:@(i)]; else [esFor(self)->fb removeObjectForKey:@(i)]; } ((Fv_onn)o)(self, s, b, off, i); POST }); });
  hk(c, "setVertexBuffer:offset:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, id b, NSUInteger off, NSUInteger i) { PRE { if (b) [esFor(self)->vb setObject:@[b, @(off)] forKey:@(i)]; else [esFor(self)->vb removeObjectForKey:@(i)]; } ((Fv_onn)o)(self, s, b, off, i); POST }); });
  hk(c, "setFragmentBufferOffset:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger off, NSUInteger i) { PRE { ES *e = esFor(self); id v = [e->fb objectForKey:@(i)]; if ([v isKindOfClass:[NSArray class]]) [e->fb setObject:@[[(NSArray *)v objectAtIndex:0], @(off)] forKey:@(i)]; } ((Fv_nn)o)(self, s, off, i); POST }); });
  hk(c, "setVertexBufferOffset:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger off, NSUInteger i) { PRE { ES *e = esFor(self); id v = [e->vb objectForKey:@(i)]; if ([v isKindOfClass:[NSArray class]]) [e->vb setObject:@[[(NSArray *)v objectAtIndex:0], @(off)] forKey:@(i)]; } ((Fv_nn)o)(self, s, off, i); POST }); });
  hk(c, "setFragmentBuffers:offsets:withRange:", ^id(IMP o, SEL s) { return BLK(^void(id self, const id *bs, const NSUInteger *os, NSRange r) { PRE { ES *e = esFor(self); for (NSUInteger j = 0; j < r.length; j++) { id b = bs ? bs[j] : nil; if (b) [e->fb setObject:@[b, @(os ? os[j] : 0)] forKey:@(r.location + j)]; else [e->fb removeObjectForKey:@(r.location + j)]; } } ((Fv_bufs)o)(self, s, bs, os, r); POST }); });
  hk(c, "setVertexBuffers:offsets:withRange:", ^id(IMP o, SEL s) { return BLK(^void(id self, const id *bs, const NSUInteger *os, NSRange r) { PRE { ES *e = esFor(self); for (NSUInteger j = 0; j < r.length; j++) { id b = bs ? bs[j] : nil; if (b) [e->vb setObject:@[b, @(os ? os[j] : 0)] forKey:@(r.location + j)]; else [e->vb removeObjectForKey:@(r.location + j)]; } } ((Fv_bufs)o)(self, s, bs, os, r); POST }); });
  hk(c, "setFragmentTexture:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, id t, NSUInteger i) { PRE { if (t) [esFor(self)->ft setObject:t forKey:@(i)]; else [esFor(self)->ft removeObjectForKey:@(i)]; } ((Fv_on)o)(self, s, t, i); POST }); });
  hk(c, "setVertexTexture:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, id t, NSUInteger i) { PRE { if (t) [esFor(self)->vt setObject:t forKey:@(i)]; else [esFor(self)->vt removeObjectForKey:@(i)]; } ((Fv_on)o)(self, s, t, i); POST }); });
  hk(c, "setFragmentTextures:withRange:", ^id(IMP o, SEL s) { return BLK(^void(id self, const id *ts, NSRange r) { PRE { ES *e = esFor(self); for (NSUInteger j = 0; j < r.length; j++) { id t = ts ? ts[j] : nil; if (t) [e->ft setObject:t forKey:@(r.location + j)]; else [e->ft removeObjectForKey:@(r.location + j)]; } } ((Fv_texs)o)(self, s, ts, r); POST }); });
  hk(c, "setViewport:", ^id(IMP o, SEL s) { return BLK(^void(id self, MTLViewport v) { PRE { esFor(self)->vp = [[NSString stringWithFormat:@"%g,%g,%g,%g", v.originX, v.originY, v.width, v.height] retain]; } ((Fv_vp)o)(self, s, v); POST }); });
  hk(c, "setScissorRect:", ^id(IMP o, SEL s) { return BLK(^void(id self, MTLScissorRect r) { PRE { esFor(self)->sc = [[NSString stringWithFormat:@"%lu,%lu,%lu,%lu", (unsigned long)r.x, (unsigned long)r.y, (unsigned long)r.width, (unsigned long)r.height] retain]; } ((Fv_sc)o)(self, s, r); POST }); });
  hk(c, "drawPrimitives:vertexStart:vertexCount:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger p, NSUInteger a, NSUInteger n) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"prim%lu v%lu+%lu", (unsigned long)p, (unsigned long)a, (unsigned long)n]); } ((Fv_n3)o)(self, s, p, a, n); POST }); });
  hk(c, "drawPrimitives:vertexStart:vertexCount:instanceCount:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger p, NSUInteger a, NSUInteger n, NSUInteger ic) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"prim%lu v%lu+%lu i%lu", (unsigned long)p, (unsigned long)a, (unsigned long)n, (unsigned long)ic]); } ((Fv_n4)o)(self, s, p, a, n, ic); POST }); });
  hk(c, "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger p, NSUInteger a, NSUInteger n, NSUInteger ic, NSUInteger bi) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"prim%lu v%lu+%lu i%lu b%lu", (unsigned long)p, (unsigned long)a, (unsigned long)n, (unsigned long)ic, (unsigned long)bi]); } ((Fv_n5)o)(self, s, p, a, n, ic, bi); POST }); });
  hk(c, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger p, NSUInteger n, NSUInteger t, id ib, NSUInteger off) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"iprim%lu n%lu t%lu ib=%@", (unsigned long)p, (unsigned long)n, (unsigned long)t, bufStr(@[ib, @(off)], YES)]); } ((Fv_di)o)(self, s, p, n, t, ib, off); POST }); });
  hk(c, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger p, NSUInteger n, NSUInteger t, id ib, NSUInteger off, NSUInteger ic) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"iprim%lu n%lu t%lu i%lu ib=%@", (unsigned long)p, (unsigned long)n, (unsigned long)t, (unsigned long)ic, bufStr(@[ib, @(off)], YES)]); } ((Fv_di6)o)(self, s, p, n, t, ib, off, ic); POST }); });
  hk(c, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:", ^id(IMP o, SEL s) { return BLK(^void(id self, NSUInteger p, NSUInteger n, NSUInteger t, id ib, NSUInteger off, NSUInteger ic, NSInteger bv, NSUInteger bi) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"iprim%lu n%lu t%lu i%lu bv%ld bi%lu ib=%@", (unsigned long)p, (unsigned long)n, (unsigned long)t, (unsigned long)ic, (long)bv, (unsigned long)bi, bufStr(@[ib, @(off)], YES)]); } ((Fv_di8)o)(self, s, p, n, t, ib, off, ic, bv, bi); POST }); });
  hk(c, "endEncoding", ^id(IMP o, SEL s) { return BLK(^void(id self) { PRE { if (gOn) LF(@"ENDENC e%d", esFor(self)->idx); [gEnc removeObjectForKey:@((uintptr_t)self)]; } ((Fv)o)(self, s); POST }); });
}

static void hookBlit(Class c) {
  if (!c || [gHookedCls containsObject:NSStringFromClass(c)]) return;
  [gHookedCls addObject:NSStringFromClass(c)];
  LF(@"HOOK blit encoder class %s", class_getName(c));
  hk(c, "generateMipmapsForTexture:", ^id(IMP o, SEL s) { return BLK(^void(id self, id t) { PRE { if (gOn) LF(@"BLIT %@ mipgen %@", gTag, TD(t)); } ((Fv_o)o)(self, s, t); POST }); });
  hk(c, "copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:", ^id(IMP o, SEL s) { return BLK(^void(id self, id a, NSUInteger sl, NSUInteger lv, MTLOrigin so, MTLSize sz, id b, NSUInteger dsl, NSUInteger dlv, MTLOrigin dor) { PRE { if (gOn) LF(@"BLIT %@ copy %@ L%lu (%lu,%lu %lux%lu) -> %@ L%lu (%lu,%lu)", gTag, TD(a), (unsigned long)lv, (unsigned long)so.x, (unsigned long)so.y, (unsigned long)sz.width, (unsigned long)sz.height, TD(b), (unsigned long)dlv, (unsigned long)dor.x, (unsigned long)dor.y); } ((Fv_ctt)o)(self, s, a, sl, lv, so, sz, b, dsl, dlv, dor); POST }); });
  hk(c, "copyFromTexture:toTexture:", ^id(IMP o, SEL s) { return BLK(^void(id self, id a, id b) { PRE { if (gOn) LF(@"BLIT %@ copyall %@ -> %@", gTag, TD(a), TD(b)); } ((Fv_oo)o)(self, s, a, b); POST }); });
  hk(c, "copyFromTexture:sourceSlice:sourceLevel:toTexture:destinationSlice:destinationLevel:sliceCount:levelCount:", ^id(IMP o, SEL s) { return BLK(^void(id self, id a, NSUInteger sl, NSUInteger lv, id b, NSUInteger dsl, NSUInteger dlv, NSUInteger sc, NSUInteger lc) { PRE { if (gOn) LF(@"BLIT %@ copylv %@ L%lu -> %@ L%lu n%lu", gTag, TD(a), (unsigned long)lv, TD(b), (unsigned long)dlv, (unsigned long)lc); } ((Fv_ctl)o)(self, s, a, sl, lv, b, dsl, dlv, sc, lc); POST }); });
}

static void hookCompute(Class c) {
  if (!c || [gHookedCls containsObject:NSStringFromClass(c)]) return;
  [gHookedCls addObject:NSStringFromClass(c)];
  LF(@"HOOK compute encoder class %s", class_getName(c));
  hk(c, "setComputePipelineState:", ^id(IMP o, SEL s) { return BLK(^void(id self, id p) { PRE { esFor(self)->pso = (void *)p; } ((Fv_o)o)(self, s, p); POST }); });
  hk(c, "setBytes:length:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, const void *b, NSUInteger n, NSUInteger i) { PRE { if (b) [esFor(self)->fb setObject:[NSData dataWithBytes:b length:n] forKey:@(i)]; } ((Fv_pnn)o)(self, s, b, n, i); POST }); });
  hk(c, "setBuffer:offset:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, id b, NSUInteger off, NSUInteger i) { PRE { if (b) [esFor(self)->fb setObject:@[b, @(off)] forKey:@(i)]; } ((Fv_onn)o)(self, s, b, off, i); POST }); });
  hk(c, "setTexture:atIndex:", ^id(IMP o, SEL s) { return BLK(^void(id self, id t, NSUInteger i) { PRE { if (t) [esFor(self)->ft setObject:t forKey:@(i)]; } ((Fv_on)o)(self, s, t, i); POST }); });
  hk(c, "dispatchThreadgroups:threadsPerThreadgroup:", ^id(IMP o, SEL s) { return BLK(^void(id self, MTLSize g, MTLSize t) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"DISPATCH tg%lux%lux%lu t%lux%lux%lu", (unsigned long)g.width, (unsigned long)g.height, (unsigned long)g.depth, (unsigned long)t.width, (unsigned long)t.height, (unsigned long)t.depth]); } ((Fv_ss)o)(self, s, g, t); POST }); });
  hk(c, "dispatchThreads:threadsPerThreadgroup:", ^id(IMP o, SEL s) { return BLK(^void(id self, MTLSize g, MTLSize t) { PRE { if (gOn) logDraw(self, [NSString stringWithFormat:@"DISPATCHT n%lux%lux%lu t%lux%lux%lu", (unsigned long)g.width, (unsigned long)g.height, (unsigned long)g.depth, (unsigned long)t.width, (unsigned long)t.height, (unsigned long)t.depth]); } ((Fv_ss)o)(self, s, g, t); POST }); });
  hk(c, "endEncoding", ^id(IMP o, SEL s) { return BLK(^void(id self) { PRE { [gEnc removeObjectForKey:@((uintptr_t)self)]; } ((Fv)o)(self, s); POST }); });
}

static NSString *rpDesc(MTLRenderPassDescriptor *d) {
  if (!d) return @"nil";
  MTLRenderPassColorAttachmentDescriptor *a = [[d colorAttachments] objectAtIndexedSubscript:0];
  MTLClearColor cc = [a clearColor];
  return [NSString stringWithFormat:@"%@ L%lu s%lu load%lu store%lu clear(%g,%g,%g,%g) resolve=%@", TD([a texture]), (unsigned long)[a level], (unsigned long)[a slice], (unsigned long)[a loadAction], (unsigned long)[a storeAction], cc.red, cc.green, cc.blue, cc.alpha, [a resolveTexture] ? TD([a resolveTexture]) : @"-"];
}
static void onRenderEncoder(id e, MTLRenderPassDescriptor *d, const char *how) {
  if (!e) return;
  hookRender(object_getClass(e));
  [gEnc removeObjectForKey:@((uintptr_t)e)];
  ES *s = esFor(e);
  s->rt = [rpDesc(d) retain];
  id t = d ? [[[d colorAttachments] objectAtIndexedSubscript:0] texture] : nil;
  s->rtTex = [t retain];
  if (gOn) LF(@"ENC %@ e%d %s rt=%@", gTag, s->idx, how, s->rt);
}
static void hookParallel(Class c) {
  if (!c || [gHookedCls containsObject:NSStringFromClass(c)]) return;
  [gHookedCls addObject:NSStringFromClass(c)];
  LF(@"HOOK parallel encoder class %s", class_getName(c));
  hk(c, "renderCommandEncoder", ^id(IMP o, SEL s) { return BLK(^id(id self) { id e = ((Fo)o)(self, s); PRE { onRenderEncoder(e, nil, "parallel-sub"); } POST return e; }); });
}
static void hookCmdBuf(Class c) {
  if (!c || [gHookedCls containsObject:NSStringFromClass(c)]) return;
  [gHookedCls addObject:NSStringFromClass(c)];
  LF(@"HOOK command buffer class %s", class_getName(c));
  hk(c, "renderCommandEncoderWithDescriptor:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d) { id e = ((Fo_o)o)(self, s, d); PRE { onRenderEncoder(e, d, "render"); } POST return e; }); });
  hk(c, "parallelRenderCommandEncoderWithDescriptor:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d) { id e = ((Fo_o)o)(self, s, d); PRE { if (e) hookParallel(object_getClass(e)); if (gOn) LF(@"ENC %@ parallel rt=%@", gTag, rpDesc(d)); } POST return e; }); });
  hk(c, "blitCommandEncoder", ^id(IMP o, SEL s) { return BLK(^id(id self) { id e = ((Fo)o)(self, s); PRE { if (e) hookBlit(object_getClass(e)); if (gOn) LF(@"ENC %@ blit", gTag); } POST return e; }); });
  hk(c, "blitCommandEncoderWithDescriptor:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d) { id e = ((Fo_o)o)(self, s, d); PRE { if (e) hookBlit(object_getClass(e)); if (gOn) LF(@"ENC %@ blitd", gTag); } POST return e; }); });
  hk(c, "computeCommandEncoder", ^id(IMP o, SEL s) { return BLK(^id(id self) { id e = ((Fo)o)(self, s); PRE { if (e) hookCompute(object_getClass(e)); if (gOn) LF(@"ENC %@ compute", gTag); } POST return e; }); });
  hk(c, "computeCommandEncoderWithDispatchType:", ^id(IMP o, SEL s) { return BLK(^id(id self, NSUInteger t) { id e = ((Fo_n)o)(self, s, t); PRE { if (e) hookCompute(object_getClass(e)); if (gOn) LF(@"ENC %@ compute%lu", gTag, (unsigned long)t); } POST return e; }); });
  hk(c, "computeCommandEncoderWithDescriptor:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d) { id e = ((Fo_o)o)(self, s, d); PRE { if (e) hookCompute(object_getClass(e)); if (gOn) LF(@"ENC %@ computed", gTag); } POST return e; }); });
  hk(c, "commit", ^id(IMP o, SEL s) { return BLK(^void(id self) { PRE { if (gOn) LF(@"COMMIT %@ cb%p", gTag, self); } ((Fv)o)(self, s); POST }); });
}

static NSString *pdDesc(MTLRenderPipelineDescriptor *d) {
  MTLRenderPipelineColorAttachmentDescriptor *a = [[d colorAttachments] objectAtIndexedSubscript:0];
  NSString *vf = [[d vertexFunction] name], *ff = [[d fragmentFunction] name];
  return [NSString stringWithFormat:@"%@ / %@ [lbl=%@ fmt%lu blend%d rgb(%lu,%lu,op%lu) a(%lu,%lu,op%lu) wm%lu]", vf ? vf : @"-", ff ? ff : @"-", [d label] ? [d label] : @"-", (unsigned long)[a pixelFormat], (int)[a isBlendingEnabled], (unsigned long)[a sourceRGBBlendFactor], (unsigned long)[a destinationRGBBlendFactor], (unsigned long)[a rgbBlendOperation], (unsigned long)[a sourceAlphaBlendFactor], (unsigned long)[a destinationAlphaBlendFactor], (unsigned long)[a alphaBlendOperation], (unsigned long)[a writeMask]];
}
static void notePipe(id p, NSString *desc, const char *how) {
  if (!p) return;
  @synchronized (gPipe) { [gPipe setObject:desc forKey:@((uintptr_t)p)]; }
  LF(@"PSO %p %s %@", p, how, desc);
}
static void hookDevice(Class c) {
  LF(@"HOOK device class %s", class_getName(c));
  hk(c, "newRenderPipelineStateWithDescriptor:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d, NSError **er) { id p = ((Fo_oe)o)(self, s, d, er); notePipe(p, pdDesc(d), "sync"); return p; }); });
  hk(c, "newRenderPipelineStateWithDescriptor:options:reflection:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d, NSUInteger op, id *rf, NSError **er) { id p = ((Fo_onre)o)(self, s, d, op, rf, er); notePipe(p, pdDesc(d), "syncR"); return p; }); });
  hk(c, "newRenderPipelineStateWithDescriptor:completionHandler:", ^id(IMP o, SEL s) { return BLK(^void(id self, id d, id h) {
    NSString *desc = [pdDesc(d) retain]; void (^hh)(id, NSError *) = h;
    void (^w)(id, NSError *) = ^(id p, NSError *e) { notePipe(p, desc, "async"); if (hh) hh(p, e); };
    ((Fv_oh)o)(self, s, d, [[w copy] autorelease]); }); });
  hk(c, "newRenderPipelineStateWithDescriptor:options:completionHandler:", ^id(IMP o, SEL s) { return BLK(^void(id self, id d, NSUInteger op, id h) {
    NSString *desc = [pdDesc(d) retain]; void (^hh)(id, id, NSError *) = h;
    void (^w)(id, id, NSError *) = ^(id p, id r, NSError *e) { notePipe(p, desc, "asyncR"); if (hh) hh(p, r, e); };
    ((Fv_onh)o)(self, s, d, op, [[w copy] autorelease]); }); });
  hk(c, "newComputePipelineStateWithFunction:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id f, NSError **er) { id p = ((Fo_oe)o)(self, s, f, er); notePipe(p, [NSString stringWithFormat:@"compute %@", [f name]], "csync"); return p; }); });
  hk(c, "newComputePipelineStateWithFunction:options:reflection:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id f, NSUInteger op, id *rf, NSError **er) { id p = ((Fo_onre)o)(self, s, f, op, rf, er); notePipe(p, [NSString stringWithFormat:@"compute %@", [f name]], "csyncR"); return p; }); });
  hk(c, "newComputePipelineStateWithDescriptor:options:reflection:error:", ^id(IMP o, SEL s) { return BLK(^id(id self, id d, NSUInteger op, id *rf, NSError **er) { id p = ((Fo_onre)o)(self, s, d, op, rf, er); notePipe(p, [NSString stringWithFormat:@"compute %@", [[d computeFunction] name]], "cdesc"); return p; }); });
  hk(c, "newComputePipelineStateWithFunction:completionHandler:", ^id(IMP o, SEL s) { return BLK(^void(id self, id f, id h) {
    NSString *desc = [[NSString stringWithFormat:@"compute %@", [f name]] retain]; void (^hh)(id, NSError *) = h;
    void (^w)(id, NSError *) = ^(id p, NSError *e) { notePipe(p, desc, "casync"); if (hh) hh(p, e); };
    ((Fv_oh)o)(self, s, f, [[w copy] autorelease]); }); });
}

static NSUInteger bppFor(NSUInteger f) {
  switch (f) {
    case 10: case 11: case 12: case 13: return 1;
    case 20: case 22: case 25: case 30: case 31: return 2;
    case 53: case 55: case 60: case 65: case 70: case 71: case 80: case 81: case 90: case 92: case 93: case 94: case 554: case 555: return 4;
    case 105: case 110: case 115: case 552: case 553: return 8;
    case 125: return 16;
    default: return 0;
  }
}
static float h2f(uint16_t h) {
  uint32_t sg = (h >> 15) & 1, e = (h >> 10) & 31, m = h & 1023; float v;
  if (e == 0) v = ldexpf((float)m, -24); else if (e == 31) v = m ? NAN : INFINITY; else v = ldexpf((float)(m | 1024), (int)e - 25);
  return sg ? -v : v;
}
static uint8_t q8(float v) { if (!(v > 0)) v = 0; if (v > 1) v = 1; return (uint8_t)lrintf(v * 255.f); }
static void toRGBA8(const uint8_t *src, NSUInteger fmt, NSUInteger w, NSUInteger h, uint8_t *dst) {
  for (NSUInteger i = 0; i < w * h; i++) {
    uint8_t *o = dst + 4 * i;
    if (fmt == 80 || fmt == 81) { const uint8_t *p = src + 4 * i; o[0] = p[2]; o[1] = p[1]; o[2] = p[0]; o[3] = p[3]; }
    else if (fmt == 70 || fmt == 71) { memcpy(o, src + 4 * i, 4); }
    else if (fmt == 115) { const uint16_t *p = (const uint16_t *)(src + 8 * i); for (int k = 0; k < 4; k++) o[k] = q8(h2f(p[k])); }
    else if (fmt == 125) { const float *p = (const float *)(src + 16 * i); for (int k = 0; k < 4; k++) o[k] = q8(p[k]); }
    else if (fmt == 25) { o[0] = o[1] = o[2] = q8(h2f(*(const uint16_t *)(src + 2 * i))); o[3] = 255; }
    else if (fmt == 10) { o[0] = o[1] = o[2] = src[i]; o[3] = 255; }
    else if (fmt == 30) { o[0] = src[2 * i]; o[1] = src[2 * i + 1]; o[2] = 0; o[3] = 255; }
    else { o[0] = o[1] = o[2] = 0; o[3] = 255; }
  }
}
static void writePNG(NSString *path, const uint8_t *rgba, NSUInteger w, NSUInteger h, BOOL premul) {
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = CGBitmapContextCreate((void *)rgba, w, h, 8, w * 4, cs, premul ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast);
  if (!ctx) { CGColorSpaceRelease(cs); LF(@"PNG ctx fail %@", path); return; }
  CGImageRef img = CGBitmapContextCreateImage(ctx);
  CGImageDestinationRef d = CGImageDestinationCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
  if (d && img) { CGImageDestinationAddImage(d, img, NULL); CGImageDestinationFinalize(d); }
  if (d) CFRelease(d); if (img) CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
}
static void writeCG(NSString *path, CGImageRef img) {
  CGImageDestinationRef d = CGImageDestinationCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
  if (d && img) { CGImageDestinationAddImage(d, img, NULL); CGImageDestinationFinalize(d); }
  if (d) CFRelease(d);
}
static void readTex(id<MTLTexture> t, NSString *tag, BOOL raw) {
  @try {
    if ([t textureType] != MTLTextureType2D) { LF(@"READ skip %@ type%lu", tag, (unsigned long)[t textureType]); return; }
    NSUInteger fmt = [t pixelFormat], bpp = bppFor(fmt);
    if (!bpp) { LF(@"READ skip %@ fmt%lu", tag, (unsigned long)fmt); return; }
    for (NSUInteger l = 0; l < [t mipmapLevelCount]; l++) {
      NSUInteger w = MAX((NSUInteger)1, [t width] >> l), h = MAX((NSUInteger)1, [t height] >> l);
      NSUInteger bpr = w * bpp, len = bpr * h;
      id<MTLBuffer> b = [gDev newBufferWithLength:len options:MTLResourceStorageModeShared];
      id<MTLCommandBuffer> cb = [gQ commandBuffer];
      id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
      [be copyFromTexture:t sourceSlice:0 sourceLevel:l sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1) toBuffer:b destinationOffset:0 destinationBytesPerRow:bpr destinationBytesPerImage:len];
      [be endEncoding]; [cb commit]; [cb waitUntilCompleted];
      if ([cb status] == MTLCommandBufferStatusError) { LF(@"READ cberr %@ L%lu %@", tag, (unsigned long)l, [cb error]); [b release]; continue; }
      NSString *base = [NSString stringWithFormat:@"%@/tex/%@_L%lu_%lux%lu_f%lu", gDir, tag, (unsigned long)l, (unsigned long)w, (unsigned long)h, (unsigned long)fmt];
      if (raw) [[NSData dataWithBytesNoCopy:[b contents] length:len freeWhenDone:NO] writeToFile:[base stringByAppendingString:@".bin"] atomically:NO];
      uint8_t *rgba = (uint8_t *)malloc(w * h * 4); toRGBA8((const uint8_t *)[b contents], fmt, w, h, rgba);
      writePNG([base stringByAppendingString:@".png"], rgba, w, h, NO); free(rgba);
      [b release];
      LF(@"READ %@ L%lu %lux%lu f%lu ok", tag, (unsigned long)l, (unsigned long)w, (unsigned long)h, (unsigned long)fmt);
    }
  } @catch (NSException *e) { LF(@"READ fail %@ %@", tag, [e reason]); }
}

// ---------- scene helpers ----------
static NSString *D(id v) { @try { return v ? [[v description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"<nil>"; } @catch (NSException *e) { return @"<ex>"; } }
static id KV(id o, NSString *k) { @try { return [o valueForKey:k]; } @catch (NSException *e) { return nil; } }
static void walk(CALayer *l, NSString *path, int d) {
  if (!l || d > 24) return;
  NSMutableString *m = [NSMutableString stringWithFormat:@"LAYER %@ %@ frame=%@ op=%g hid=%d corner=%g masks=%d scale=%g subs=%lu", path, NSStringFromClass([l class]), NSStringFromRect(NSRectFromCGRect([l frame])), [l opacity], (int)[l isHidden], [l cornerRadius], (int)[l masksToBounds], [l contentsScale], (unsigned long)[[l sublayers] count]];
  if ([l name]) [m appendFormat:@" name=%@", [l name]];
  if ([[l filters] count]) { [m appendString:@" filters="]; for (id f in [l filters]) [m appendFormat:@"%@/%@,", D(KV(f, @"type")), D(KV(f, @"name"))]; }
  if ([l compositingFilter]) [m appendFormat:@" comp=%@", D(KV([l compositingFilter], @"type"))];
  NSString *cn = NSStringFromClass([l class]);
  if ([cn rangeOfString:@"Backdrop"].location != NSNotFound) for (NSString *k in @[@"scale", @"groupName", @"marginWidth", @"enabled", @"captureOnly", @"bleedAmount", @"zoom"]) [m appendFormat:@" %@=%@", k, D(KV(l, k))];
  if ([l respondsToSelector:NSSelectorFromString(@"effect")]) { id e = KV(l, @"effect"); if (e) [m appendFormat:@" effect=%@", NSStringFromClass([e class])]; }
  LS(m);
  NSUInteger i = 0; for (CALayer *s in [l sublayers]) { walk(s, [NSString stringWithFormat:@"%@.%lu", path, (unsigned long)i], d + 1); i++; }
  if ([l mask]) walk([l mask], [path stringByAppendingString:@".mask"], d + 1);
}
static CALayer *cloneTree(CALayer *l) {
  CALayer *c = nil;
  @try { c = [[[l class] alloc] initWithLayer:l]; } @catch (NSException *e) { LF(@"clone ex %@ %@", NSStringFromClass([l class]), [e reason]); c = [[CALayer alloc] init]; }
  NSArray *subs = [[[l sublayers] copy] autorelease];
  if ([[c sublayers] count]) LF(@"clone note: %@ initWithLayer kept %lu sublayers", NSStringFromClass([l class]), (unsigned long)[[c sublayers] count]);
  for (CALayer *s in subs) [c addSublayer:cloneTree(s)];
  if ([l mask]) [c setMask:cloneTree([l mask])];
  return [c autorelease];
}
static void setScaleRec(CALayer *l, CGFloat s) { [l setContentsScale:s]; [l setRasterizationScale:s]; for (CALayer *x in [l sublayers]) setScaleRec(x, s); if ([l mask]) setScaleRec([l mask], s); }

static NSWindow *gWin; static NSView *gHost;
static void setupWin(void) {
  [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp finishLaunching];
  gWin = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 1500, 260) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  gHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1500, 260)]; [gHost setWantsLayer:YES];
  [gWin setContentView:gHost]; [gWin setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
  [NSApp activateIgnoringOtherApps:YES]; [gWin makeKeyAndOrderFront:nil]; pump(1.0);
}

// Synthetic, pixel-exact backdrop: W x H pixels, top-left origin as stored.
static CGImageRef patternImage(int W, int H, int unit) {
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextSetRGBFillColor(c, 1, 1, 1, 1); CGContextFillRect(c, CGRectMake(0, 0, W, H));
  for (int x = 0; x < W; x += 24 * unit) { CGContextSetRGBFillColor(c, 0, 0, 0, 1); CGContextFillRect(c, CGRectMake(x, 0, 6 * unit, H)); }
  for (int y = 6 * unit, i = 0; y < H; y += 30 * unit, i++) {
    CGFloat hue = (i % 6) / 6.0; NSColor *col = [[NSColor colorWithCalibratedHue:hue saturation:1 brightness:0.95 alpha:1] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGContextSetRGBFillColor(c, [col redComponent], [col greenComponent], [col blueComponent], 1); CGContextFillRect(c, CGRectMake(0, y, W, 10 * unit));
  }
  for (int x = 0; x < W / 3; x++) { CGFloat g = (CGFloat)x / (W / 3); CGContextSetRGBFillColor(c, g, g, g, 1); CGContextFillRect(c, CGRectMake(x, 0, 1, H / 4)); }
  CGContextSetRGBFillColor(c, 0.05, 0.08, 0.12, 1); CGContextFillRect(c, CGRectMake(W * 0.62, H * 0.1, W * 0.18, H * 0.8));
  CGImageRef img = CGBitmapContextCreateImage(c); CGContextRelease(c); CGColorSpaceRelease(cs); return img;
}
static CGImageRef gTahoe = NULL;
static CGImageRef tahoeFrame(double t, int maxDim) {
  NSURL *u = [NSURL fileURLWithPath:@"/System/Library/Desktop Pictures/.wallpapers/Tahoe Day/Tahoe Day.mov"];
  AVURLAsset *a = [AVURLAsset URLAssetWithURL:u options:nil];
  AVAssetImageGenerator *g = [[AVAssetImageGenerator alloc] initWithAsset:a];
  [g setRequestedTimeToleranceBefore:kCMTimeZero]; [g setRequestedTimeToleranceAfter:kCMTimeZero]; [g setAppliesPreferredTrackTransform:YES];
  if (maxDim) [g setMaximumSize:CGSizeMake(maxDim, maxDim)];
  __block CGImageRef out = NULL; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [g generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(t, 600) completionHandler:^(CGImageRef im, CMTime act, NSError *err) {
    if (im) out = CGImageRetain(im);
    LF(@"TAHOE t=%g act=%g img=%zux%zu err=%@", t, CMTimeGetSeconds(act), im ? CGImageGetWidth(im) : 0, im ? CGImageGetHeight(im) : 0, err);
    dispatch_semaphore_signal(sem); }];
  long r = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
  if (r) LF(@"TAHOE timeout t=%g", t);
  if (out) { CGColorSpaceRef cs = CGImageGetColorSpace(out); CFStringRef nm = cs ? CGColorSpaceCopyName(cs) : NULL; LF(@"TAHOE colorspace=%@ bpc=%zu bpp=%zu alpha=%d", nm ? (NSString *)nm : @"?", CGImageGetBitsPerComponent(out), CGImageGetBitsPerPixel(out), (int)CGImageGetAlphaInfo(out)); if (nm) CFRelease(nm); }
  [g release]; return out;
}
// Draw img aspect-filled into a screenW x screenH pixel screen, return bottom strip (stripH px) as a pixel-exact image.
static CGImageRef tahoeStrip(CGImageRef img, int screenW, int screenH, int stripH) {
  CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef c = CGBitmapContextCreate(NULL, screenW, stripH, 8, screenW * 4, cs, kCGImageAlphaPremultipliedLast);
  CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
  double iw = CGImageGetWidth(img), ih = CGImageGetHeight(img), s = fmax(screenW / iw, screenH / ih);
  double dw = iw * s, dh = ih * s;
  CGContextDrawImage(c, CGRectMake((screenW - dw) / 2, (screenH - dh) / 2, dw, dh), img);  // CG origin bottom-left; strip = screen rows [screenH-stripH, screenH)
  CGImageRef out = CGBitmapContextCreateImage(c); CGContextRelease(c); CGColorSpaceRelease(cs);
  LF(@"STRIP screen %dx%d strip %d scale %.6f draw %.2fx%.2f at %.2f,%.2f", screenW, screenH, stripH, s, dw, dh, (screenW - dw) / 2, (screenH - dh) / 2);
  return out;
}

static void renderFrame(CALayer *root, int W, int H, NSString *tag) {
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO];
  [td setUsage:MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite]; [td setStorageMode:MTLStorageModePrivate];
  id<MTLTexture> tex = [gDev newTextureWithDescriptor:td];
  NSMutableDictionary *opt = [NSMutableDictionary dictionary];
  NSString **kcs = (NSString **)dlsym(RTLD_DEFAULT, "kCARendererColorSpace");
  NSString **kq = (NSString **)dlsym(RTLD_DEFAULT, "kCARendererMetalCommandQueue");
  if (kcs && *kcs && gCS) [opt setObject:(id)gCS forKey:*kcs];
  if (kq && *kq) [opt setObject:gQ forKey:*kq];
  CARenderer *r = [CARenderer rendererWithMTLTexture:tex options:opt];
  [r setLayer:root]; [r setBounds:CGRectMake(0, 0, W, H)];
  [CATransaction flush];
  [gTag release]; gTag = [tag retain]; gDraw = 0; [gRead removeAllObjects];
  LF(@"FRAME %@ begin %dx%d opts=%lu", tag, W, H, (unsigned long)[opt count]);
  double t0 = nowS();
  gOn = 1;
  [r beginFrameAtTime:CACurrentMediaTime() timeStamp:NULL];
  [r addUpdateRect:[r bounds]];
  [r render];
  [r endFrame];
  id<MTLCommandBuffer> cb = [gQ commandBuffer]; [cb commit]; [cb waitUntilCompleted];
  gOn = 0;
  LF(@"FRAME %@ end draws=%d reads=%lu %.3fs", tag, gDraw, (unsigned long)[gRead count], nowS() - t0);
  readTex(tex, [tag stringByAppendingString:@"_out"], NO);
  for (NSArray *rd in [[gRead copy] autorelease]) readTex([rd objectAtIndex:0], [rd objectAtIndex:1], YES);
  [r setLayer:nil];
  [tex release];
}

static BOOL scene(NSString *tag, CGImageRef bg, CGSize ptSize, CGRect gf, double radius, long variant, double scale, NSString *strategy) {
  Class G = NSClassFromString(@"NSGlassEffectView");
  if (!G) { LF(@"no NSGlassEffectView"); return NO; }
  NSView *g = [[G alloc] initWithFrame:NSMakeRect(20, 20, gf.size.width, gf.size.height)];
  @try { [g setValue:@(radius) forKey:@"cornerRadius"]; } @catch (NSException *e) { LF(@"cornerRadius ex %@", [e reason]); }
  if (variant >= 0) { @try { [g setValue:@(variant) forKey:@"_variant"]; } @catch (NSException *e) { LF(@"variant ex %@", [e reason]); } }
  [gHost addSubview:g]; pump(0.8);
  CALayer *gl = [g layer];
  LF(@"SCENE %@ variant=%ld readback=%@ radius=%g glass=%@ pts=%gx%g scale=%g strategy=%@ appearance=%@", tag, variant, D(KV(g, @"_variant")), radius, NSStringFromRect(NSRectFromCGRect(gf)), ptSize.width, ptSize.height, scale, strategy, [[g effectiveAppearance] name]);
  walk(gl, @"g", 0);
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
  CALayer *glass = nil;
  if ([strategy isEqualToString:@"clone"]) glass = cloneTree(gl);
  else if ([strategy isEqualToString:@"detach"]) { [gl retain]; [g removeFromSuperview]; [gl removeFromSuperlayer]; glass = [gl autorelease]; }
  else { [gl retain]; [gl removeFromSuperlayer]; glass = [gl autorelease]; }
  [glass setFrame:gf];
  setScaleRec(glass, scale);
  [cont addSublayer:glass];
  [CATransaction flush];
  [glass setFrame:gf];
  renderFrame(root, (int)lround(ptSize.width * scale), (int)lround(ptSize.height * scale), tag);
  [glass removeFromSuperlayer];
  if ([g superview]) [g removeFromSuperview];
  [g release];
  pump(0.1);
  return YES;
}

int main(int argc, const char **argv) { @autoreleasepool {
  if (argc < 4) { fprintf(stderr, "usage: cap outdir strategy mode\n"); return 2; }
  gDir = [[NSString stringWithUTF8String:argv[1]] retain];
  NSString *strategy = [NSString stringWithUTF8String:argv[2]], *mode = [NSString stringWithUTF8String:argv[3]];
  [[NSFileManager defaultManager] createDirectoryAtPath:[gDir stringByAppendingPathComponent:@"tex"] withIntermediateDirectories:YES attributes:nil error:nil];
  [[NSFileManager defaultManager] createDirectoryAtPath:[gDir stringByAppendingPathComponent:@"img"] withIntermediateDirectories:YES attributes:nil error:nil];
  gL = fopen([[gDir stringByAppendingPathComponent:@"log.txt"] fileSystemRepresentation], "w"); if (!gL) gL = stdout;
  double deadline = (argc > 4) ? atof(argv[4]) : 300;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(deadline * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{ LF(@"WATCHDOG exit"); fflush(gL); _exit(3); });
  gPipe = [NSMutableDictionary new]; gEnc = [NSMutableDictionary new]; gRead = [NSMutableArray new]; gHooked = [NSMutableSet new]; gHookedCls = [NSMutableSet new];
  gCS = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  gDev = MTLCreateSystemDefaultDevice(); gQ = [gDev newCommandQueue];
  LF(@"DEVICE %@ class=%s lowPower=%d unified=%d", [gDev name], class_getName(object_getClass(gDev)), (int)[gDev isLowPower], (int)[gDev hasUnifiedMemory]);
  hookDevice(object_getClass(gDev));
  { id<MTLCommandBuffer> cb = [gQ commandBuffer]; hookCmdBuf(object_getClass(cb));
    id<MTLCommandBuffer> cb2 = [gQ commandBufferWithUnretainedReferences]; hookCmdBuf(object_getClass(cb2));
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:8 height:8 mipmapped:NO]; [td setUsage:MTLTextureUsageRenderTarget]; [td setStorageMode:MTLStorageModePrivate];
    id<MTLTexture> t = [gDev newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor]; [[[rp colorAttachments] objectAtIndexedSubscript:0] setTexture:t];
    id e = [cb renderCommandEncoderWithDescriptor:rp]; [e endEncoding];
    id be = [cb blitCommandEncoder]; [be endEncoding];
    id ce = [cb computeCommandEncoder]; [ce endEncoding];
    [cb commit]; [cb waitUntilCompleted]; [t release]; }
  setupWin();
  LF(@"MODE %@ strategy=%@ os=%@", mode, strategy, [[NSProcessInfo processInfo] operatingSystemVersionString]);

  CGImageRef pat1 = patternImage(700, 200, 1), pat2 = patternImage(1400, 400, 2);
  writeCG([gDir stringByAppendingPathComponent:@"img/pattern1x_700x200.png"], pat1);
  writeCG([gDir stringByAppendingPathComponent:@"img/pattern2x_1400x400.png"], pat2);
  CGRect gfp = CGRectMake(50, 64, 600, 72);
  if ([mode isEqualToString:@"probe"]) {
    scene(@"p1_v0", pat1, CGSizeMake(700, 200), gfp, 24, 0, 1, strategy);
    LF(@"DONE"); return 0;
  }
  long pv[] = {0, 2, 3, 4, 5, 6, 9, 11, 15};
  for (int i = 0; i < (int)(sizeof pv / sizeof pv[0]); i++) scene([NSString stringWithFormat:@"p1_v%ld", pv[i]], pat1, CGSizeMake(700, 200), gfp, 24, pv[i], 1, strategy);
  scene(@"p2_v0", pat2, CGSizeMake(700, 200), gfp, 24, 0, 2, strategy);
  scene(@"p2_v2", pat2, CGSizeMake(700, 200), gfp, 24, 2, 2, strategy);
  scene(@"p1_v0_r36", pat1, CGSizeMake(700, 200), gfp, 36, 0, 1, strategy);
  scene(@"p1_v0_s300x160", pat1, CGSizeMake(700, 200), CGRectMake(200, 20, 300, 160), 28, 0, 1, strategy);
  // Real wallpaper: Tahoe Day frame, aspect-filled to a 2880x1800 screen, bottom 200 px strip, Dock-sized glass at 2x.
  gTahoe = tahoeFrame(0, 0);
  if (gTahoe) {
    writeCG([gDir stringByAppendingPathComponent:@"img/tahoe_t0_full.png"], gTahoe);
    for (int k = 1; k <= 4; k++) { CGImageRef f = tahoeFrame(k * 7.5, 1024); if (f) { writeCG([gDir stringByAppendingPathComponent:[NSString stringWithFormat:@"img/tahoe_t%d_small.png", k]], f); CGImageRelease(f); } }
    CGImageRef strip = tahoeStrip(gTahoe, 2880, 1800, 200);
    writeCG([gDir stringByAppendingPathComponent:@"img/tahoe_strip_2880x200.png"], strip);
    CGRect dock = CGRectMake(48, 5.5, 1343.5, 78);
    for (long v = 0; v <= 20; v++) scene([NSString stringWithFormat:@"dock_v%ld", v], strip, CGSizeMake(1440, 100), dock, 24, v, 2, strategy);
  }
  LF(@"DONE");
  return 0;
} }
