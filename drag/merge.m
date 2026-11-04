// Glass merging reference for macOS 26: two NSGlassEffectViews inside an NSGlassEffectContainerView, moved closer step by step
// (and the same with container spacing 0 and with no container), over stripes, white and black, light and dark. Window shots only.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <unistd.h>
static FILE *LOG = NULL;
static void L(NSString *s) { if (LOG) { fprintf(LOG, "%s\n", [s UTF8String]); fflush(LOG); } }
static NSString *OUT = nil; static NSWindow *WIN = nil; static long WNUM = 0; static const CGFloat WW = 800, WH = 560;
@interface KeyWin : NSWindow
@end
@implementation KeyWin
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end
@interface Pattern : NSView
@end
@implementation Pattern
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
  NSRect b = [self bounds];
  [[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 0, WW, 150));
  CGFloat C[6][3] = {{245,245,245},{16,16,16},{128,128,128},{30,100,220},{240,140,40},{40,140,70}};
  for (int i = 0; i * 24 < WW; i++) { CGFloat *c = C[i % 6]; [[NSColor colorWithSRGBRed:c[0]/255 green:c[1]/255 blue:c[2]/255 alpha:1] setFill]; NSRectFill(NSMakeRect(i * 24, 150, 24, 260)); }
  [[NSColor blackColor] setFill]; for (int y = 150; y < 410; y += 20) NSRectFill(NSMakeRect(0, y, WW, 1));
  [[NSColor colorWithSRGBRed:16/255.0 green:16/255.0 blue:16/255.0 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 410, WW, NSHeight(b) - 410));
}
@end
static void pump(double secs) { NSDate *u = [NSDate dateWithTimeIntervalSinceNow:secs]; while ([u timeIntervalSinceNow] > 0) { NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01] inMode:NSDefaultRunLoopMode dequeue:YES]; if (e) [NSApp sendEvent:e]; } }
static void request(NSString *line) {
  NSString *ack = [OUT stringByAppendingPathComponent:@"ack.txt"]; [[NSFileManager defaultManager] removeItemAtPath:ack error:nil];
  NSString *tmp = [OUT stringByAppendingPathComponent:@"req.tmp"]; [[line stringByAppendingString:@"\n"] writeToFile:tmp atomically:NO encoding:NSUTF8StringEncoding error:nil];
  rename([tmp UTF8String], [[OUT stringByAppendingPathComponent:@"req.txt"] UTF8String]);
  int i = 0; for (; i < 400 && ![[NSFileManager defaultManager] fileExistsAtPath:ack]; i++) pump(0.02);
  if (i >= 400) L([@"ack timeout " stringByAppendingString:line]);
}
static void shoot(NSString *n) { L([@"SHOT " stringByAppendingString:n]); request([NSString stringWithFormat:@"SHOT %@ %ld", n, WNUM]); }
static NSView *glass(CGFloat r, long style) {
  Class G = NSClassFromString(@"NSGlassEffectView"); if (!G) { L(@"NO NSGlassEffectView"); return [[[NSView alloc] init] autorelease]; }
  NSView *g = [[[G alloc] initWithFrame:NSZeroRect] autorelease];
  @try { [g setValue:@(r) forKey:@"cornerRadius"]; } @catch (id e) { L(@"cornerRadius failed"); }
  @try { [g setValue:@(style) forKey:@"style"]; } @catch (id e) { L(@"style failed"); }
  @try { [g setValue:[[[NSView alloc] initWithFrame:NSZeroRect] autorelease] forKey:@"contentView"]; } @catch (id e) { L(@"glass contentView failed"); }
  return g;
}
static NSView *HOLD = nil; static NSMutableArray *GL = nil;
// rows: y (top-left) 50 over white, 220 over stripes, 450 over black. Shape A: x 120, 160 x 56, r 28. Shape B: 160 x 56 at A + 160 + gap.
// Second pair (small): 44 x 44 circle at x 560, then a 96 x 44 capsule at 560 + 44 + gap (toolbar-like).
static void layout(CGFloat gap) {
  CGFloat ys[3] = {50, 220, 450};
  for (int k = 0; k < 3; k++) {
    NSView *a = GL[k * 4], *b = GL[k * 4 + 1], *c = GL[k * 4 + 2], *d = GL[k * 4 + 3];
    [a setFrame:NSMakeRect(120, WH - ys[k] - 56, 160, 56)]; [b setFrame:NSMakeRect(120 + 160 + gap, WH - ys[k] - 56, 160, 56)];
    [c setFrame:NSMakeRect(560, WH - ys[k] - 50, 44, 44)]; [d setFrame:NSMakeRect(560 + 44 + gap * 0.5, WH - ys[k] - 50, 96, 44)];
  }
}
static void build(int config, long style) {   // config 0: container spacing 40, 1: container spacing 0, 2: no container
  for (NSView *v in [[[[WIN contentView] subviews] copy] autorelease]) if (![v isKindOfClass:[Pattern class]]) [v removeFromSuperview];
  GL = [[NSMutableArray alloc] init];
  NSView *root = [WIN contentView];
  HOLD = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, WW, WH)] autorelease];
  if (config < 2) {
    Class C = NSClassFromString(@"NSGlassEffectContainerView");
    if (!C) { L(@"NO NSGlassEffectContainerView"); [root addSubview:HOLD]; }
    else { NSView *cv = [[[C alloc] initWithFrame:NSMakeRect(0, 0, WW, WH)] autorelease];
      @try { [cv setValue:@(config == 0 ? 40.0 : 0.0) forKey:@"spacing"]; } @catch (id e) { L(@"spacing failed"); }
      @try { [cv setValue:HOLD forKey:@"contentView"]; } @catch (id e) { L(@"contentView failed"); [cv addSubview:HOLD]; }
      [root addSubview:cv];
      L([NSString stringWithFormat:@"container spacing=%@", [cv valueForKey:@"spacing"]]);
    }
  } else [root addSubview:HOLD];
  for (int k = 0; k < 3; k++) { NSView *a = glass(28, style), *b = glass(28, style), *c = glass(22, style), *d = glass(22, style); [GL addObjectsFromArray:@[a, b, c, d]]; [HOLD addSubview:a]; [HOLD addSubview:b]; [HOLD addSubview:c]; [HOLD addSubview:d]; }
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    OUT = [[NSString stringWithUTF8String:(argc > 1 ? argv[1] : ".")] retain];
    LOG = fopen([[OUT stringByAppendingPathComponent:@"log.txt"] UTF8String], "w");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(420 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{ L(@"WATCHDOG"); [@"x" writeToFile:[OUT stringByAppendingPathComponent:@"quit.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil]; _exit(0); });
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp finishLaunching];
    WIN = [[KeyWin alloc] initWithContentRect:NSMakeRect(120, 120, WW, WH) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    [WIN setHasShadow:NO]; [WIN setLevel:NSFloatingWindowLevel];
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, WW, WH)]; [root setWantsLayer:YES]; [WIN setContentView:root];
    Pattern *pat = [[Pattern alloc] initWithFrame:[root bounds]]; [root addSubview:pat];
    for (int i = 0; i < 30 && !([WIN isKeyWindow] && [NSApp isActive]); i++) { [NSApp activateIgnoringOtherApps:YES]; [WIN makeKeyAndOrderFront:nil]; pump(0.1); }
    WNUM = [WIN windowNumber];
    L([NSString stringWithFormat:@"os=%@ scale=%.1f glass=%d container=%d", [[NSProcessInfo processInfo] operatingSystemVersionString], [WIN backingScaleFactor], NSClassFromString(@"NSGlassEffectView") != nil, NSClassFromString(@"NSGlassEffectContainerView") != nil]);
    NSArray *gaps = @[@80, @60, @48, @40, @32, @24, @16, @12, @8, @4, @0, @-16, @-40];
    NSArray *runs = @[@[@"light", @0, @0, @0], @[@"dark", @1, @0, @0], @[@"light", @0, @1, @0], @[@"light", @0, @2, @0], @[@"dark", @1, @2, @0], @[@"light", @0, @0, @1], @[@"dark", @1, @0, @1]];
    for (NSArray *rn in runs) {
      NSAppearance *ap = [NSAppearance appearanceNamed:([rn[1] intValue] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)]; [WIN setAppearance:ap];
      int cfg = [rn[2] intValue]; long st = [rn[3] longValue];
      build(cfg, st); NSString *tag = [NSString stringWithFormat:@"%@_c%d_s%ld", rn[0], cfg, st];
      for (NSNumber *g in gaps) { layout([g doubleValue]); [[WIN contentView] layoutSubtreeIfNeeded]; pump(0.6); shoot([NSString stringWithFormat:@"%@_g%+03d", tag, [g intValue]]); }
      L([@"run done " stringByAppendingString:tag]);
    }
    // a slow approach with frames every 4 pt (container spacing 40, light) to see whether the bridge animates or follows the gap
    build(0, 0); NSAppearance *ap = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; [WIN setAppearance:ap];
    for (int g = 48; g >= -8; g -= 4) { layout(g); pump(0.08); shoot([NSString stringWithFormat:@"fast_g%+03d", g]); }
    L(@"done"); [@"x" writeToFile:[OUT stringByAppendingPathComponent:@"quit.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    if (LOG) fclose(LOG);
  }
  return 0;
}
