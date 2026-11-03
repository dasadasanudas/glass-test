// Drag-state capture for macOS 26 controls: press, hold, drag and release real AppKit controls with real mouse events
// (posted by a helper the shell runs) and screenshot the window at each moment. Falls back to in-app NSEvents.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>
#include <unistd.h>

static FILE *LOG = NULL;
static void L(NSString *s) { if (LOG) { fprintf(LOG, "%s\n", [s UTF8String]); fflush(LOG); } }

@interface KeyWin : NSWindow
@end
@implementation KeyWin
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface GridView : NSView
@end
@implementation GridView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    NSRect b = [self bounds];
    [[NSColor whiteColor] setFill]; NSRectFill(b);
    [[NSColor blackColor] setFill];
    for (int x = 0; x < (int)NSWidth(b); x += 8) NSRectFill(NSMakeRect(x, 0, 1, NSHeight(b)));
    for (int y = 0; y < (int)NSHeight(b); y += 8) NSRectFill(NSMakeRect(0, y, NSWidth(b), 1));
    [[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] setFill];
    for (int x = 0; x < (int)NSWidth(b); x += 40) NSRectFill(NSMakeRect(x, 0, 2, NSHeight(b)));
}
@end

@interface LogSlider : NSSlider
@end
@implementation LogSlider
- (void)mouseDown:(NSEvent *)e { L([NSString stringWithFormat:@"  slider mouseDown enter cc=%ld btn=%lu val=%.1f", (long)[e clickCount], (unsigned long)[NSEvent pressedMouseButtons], [self doubleValue]]); [super mouseDown:e]; L([NSString stringWithFormat:@"  slider mouseDown exit val=%.1f", [self doubleValue]]); }
@end

static NSString *OUT = nil;
static NSWindow *WIN = nil;
static NSView *ROOT = nil, *BASE = nil;
static GridView *GRID = nil;
static NSRect WF;
static double SH = 0;
static long WNUM = 0;
static volatile int INAPP = 0, DONE = 0;
static const CGFloat WW = 800, WH = 560;

static void pump(double secs) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:secs];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01] inMode:NSDefaultRunLoopMode dequeue:YES];
        if (e) [NSApp sendEvent:e];
    }
}
static void request(NSString *line) {
    NSString *ack = [OUT stringByAppendingPathComponent:@"ack.txt"];
    [[NSFileManager defaultManager] removeItemAtPath:ack error:nil];
    NSString *tmp = [OUT stringByAppendingPathComponent:@"req.tmp"];
    [[line stringByAppendingString:@"\n"] writeToFile:tmp atomically:NO encoding:NSUTF8StringEncoding error:nil];
    rename([tmp UTF8String], [[OUT stringByAppendingPathComponent:@"req.txt"] UTF8String]);
    BOOL mainT = [NSThread isMainThread];
    int i = 0;
    for (; i < 500 && ![[NSFileManager defaultManager] fileExistsAtPath:ack]; i++) { if (mainT) pump(0.02); else usleep(20000); }
    if (i >= 500) L([@"  ack timeout for " stringByAppendingString:line]);
}
static void shoot(NSString *name) { L([@"SHOT " stringByAppendingString:name]); request([NSString stringWithFormat:@"SHOT %@ %ld", name, WNUM]); }
static CGPoint G(NSPoint p) { return CGPointMake(NSMinX(WF) + p.x, SH - (NSMinY(WF) + p.y)); }
static void mouse(NSString *kind, NSPoint p) {
    CGPoint g = G(p);
    if (!INAPP) { request([NSString stringWithFormat:@"MOUSE %@ %.1f %.1f", kind, g.x, g.y]); return; }
    NSEventType t = [kind isEqual:@"down"] ? NSEventTypeLeftMouseDown : [kind isEqual:@"up"] ? NSEventTypeLeftMouseUp : [kind isEqual:@"drag"] ? NSEventTypeLeftMouseDragged : NSEventTypeMouseMoved;
    CGWarpMouseCursorPosition(g);
    NSEvent *e = [NSEvent mouseEventWithType:t location:p modifierFlags:0 timestamp:[[NSProcessInfo processInfo] systemUptime] windowNumber:WNUM context:nil eventNumber:0 clickCount:1 pressure:(t == NSEventTypeLeftMouseUp ? 0.0 : 1.0)];
    [NSApp postEvent:e atStart:NO];
    usleep(16000);
}
static void ensureKey(void) {
    for (int i = 0; i < 40 && !([WIN isKeyWindow] && [NSApp isActive]); i++) {
        [NSApp activateIgnoringOtherApps:YES];
        if ([NSApp respondsToSelector:@selector(activate)]) [NSApp performSelector:@selector(activate)];
        [WIN makeKeyAndOrderFront:nil]; [WIN makeMainWindow];
        pump(0.1);
    }
    pump(0.6);
}
static NSView *place(NSView *v, CGFloat x, CGFloat yTop, CGFloat w, CGFloat h) {
    if (w <= 0 || h <= 0) { [v sizeToFit]; if (w <= 0) w = NSWidth([v frame]); if (h <= 0) h = NSHeight([v frame]); }
    [v setFrame:NSMakeRect(x, WH - yTop - h, w, h)];
    [ROOT addSubview:v];
    return v;
}
static NSPoint mid(NSRect r) { return NSMakePoint(NSMidX(r), NSMidY(r)); }
static NSString *fr(NSView *v) { NSRect r = [v convertRect:[v bounds] toView:nil]; return [NSString stringWithFormat:@"%.0f %.0f %.0f %.0f", NSMinX(r), WH - NSMaxY(r), NSWidth(r), NSHeight(r)]; }

static NSSlider *SL, *SLL; static NSSwitch *SW, *SWL; static NSSegmentedControl *SEG; static NSButton *PUSH, *CHK;

static void build(void) {
    for (NSView *v in [[[ROOT subviews] copy] autorelease]) [v removeFromSuperview];
    SL = [LogSlider sliderWithValue:40 minValue:0 maxValue:100 target:nil action:nil]; place(SL, 40, 50, 320, 0);
    SLL = [LogSlider sliderWithValue:40 minValue:0 maxValue:100 target:nil action:nil]; [SLL setControlSize:NSControlSizeLarge]; place(SLL, 40, 110, 320, 0);
    SW = [[[NSSwitch alloc] init] autorelease]; place(SW, 40, 180, 0, 0);
    SWL = [[[NSSwitch alloc] init] autorelease]; [SWL setControlSize:NSControlSizeLarge]; place(SWL, 160, 176, 0, 0);
    SEG = [NSSegmentedControl segmentedControlWithLabels:@[@"One", @"Two", @"Three"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
    [SEG setSelectedSegment:0]; place(SEG, 40, 250, 0, 0);
    PUSH = [NSButton buttonWithTitle:@"Button" target:nil action:nil]; [PUSH setBezelStyle:NSBezelStylePush]; place(PUSH, 40, 320, 0, 0);
    CHK = [NSButton checkboxWithTitle:@"Checkbox" target:nil action:nil]; place(CHK, 200, 322, 0, 0);
    L([NSString stringWithFormat:@"FRAMES slider %@ | slider_large %@ | switch %@ | switch_large %@ | segmented %@ | push %@ | checkbox %@", fr(SL), fr(SLL), fr(SW), fr(SWL), fr(SEG), fr(PUSH), fr(CHK)]);
}
static NSPoint knob(NSSlider *s) {
    NSSliderCell *c = (NSSliderCell *)[s cell];
    NSRect kr = [c knobRectFlipped:[s isFlipped]];
    NSRect w = [s convertRect:kr toView:nil];
    L([NSString stringWithFormat:@"  knob rect %.1f %.1f %.1f %.1f (window, top-left y %.1f)", NSMinX(w), NSMinY(w), NSWidth(w), NSHeight(w), WH - NSMaxY(w)]);
    return mid(w);
}
static void resetMain(void) { dispatch_sync(dispatch_get_main_queue(), ^{ [SL setDoubleValue:40]; [SLL setDoubleValue:40]; [SW setState:0]; [SWL setState:0]; [SEG setSelectedSegment:0]; [CHK setState:0]; [ROOT setNeedsDisplay:YES]; }); usleep(500000); }

static void dumpL(CALayer *l, int dep, NSMutableString *o) {
    if (dep > 6) return;
    [o appendFormat:@"%*s%@ name=%@ f=%.1f,%.1f,%.1f,%.1f op=%.2f filters=%lu bg=%@\n", dep * 2, "", NSStringFromClass([l class]), [l name], l.frame.origin.x, l.frame.origin.y, l.frame.size.width, l.frame.size.height, l.opacity, (unsigned long)[[l filters] count], l.backgroundColor ? @"y" : @"n"];
    for (CALayer *s in [l sublayers]) dumpL(s, dep + 1, o);
}
static void dumpV(NSView *v, int dep, NSMutableString *o) {
    if (dep > 5) return;
    [o appendFormat:@"%*sV %@ f=%.1f,%.1f,%.1f,%.1f\n", dep * 2, "", NSStringFromClass([v class]), NSMinX([v frame]), NSMinY([v frame]), NSWidth([v frame]), NSHeight([v frame])];
    for (NSView *s in [v subviews]) dumpV(s, dep + 1, o);
}
static void dumpTree(NSString *tag, NSView *v) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableString *o = [NSMutableString stringWithFormat:@"TREE %@\n", tag];
        dumpV(v, 0, o); if ([v layer]) dumpL([v layer], 0, o);
        L(o);
    });
}
static void burst(NSString *tag, NSPoint a);
static void scene(NSString *tag, NSPoint a, NSPoint b, BOOL drag) {
    mouse(@"move", a); usleep(300000);
    shoot([tag stringByAppendingString:@"_0_idle"]);
    mouse(@"down", a); usleep(100000);
    shoot([tag stringByAppendingString:@"_1_down"]);
    usleep(500000);
    shoot([tag stringByAppendingString:@"_2_held"]);
    NSPoint end = a;
    if (drag) {
        for (int i = 1; i <= 8; i++) { double t = 0.5 * i / 8.0; mouse(@"drag", NSMakePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)); usleep(15000); }
        shoot([tag stringByAppendingString:@"_3_mid"]);
        L([NSString stringWithFormat:@"  mid slider %.1f btn=%lu", [SL doubleValue], (unsigned long)[NSEvent pressedMouseButtons]]);
        if ([tag hasSuffix:@"_slider"] || [tag hasSuffix:@"switch_drag"]) dumpTree(tag, [tag hasSuffix:@"_slider"] ? (NSView *)SL : (NSView *)SW);
        for (int i = 1; i <= 8; i++) { double t = 0.5 + 0.5 * i / 8.0; mouse(@"drag", NSMakePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)); usleep(15000); }
        usleep(450000);
        shoot([tag stringByAppendingString:@"_4_endheld"]);
        end = b;
    }
    mouse(@"up", end); usleep(50000);
    shoot([tag stringByAppendingString:@"_5_up"]);
    usleep(700000);
    shoot([tag stringByAppendingString:@"_6_after"]);
    L([NSString stringWithFormat:@"VALUES %@ slider %.1f slider_large %.1f switch %ld switch_large %ld seg %ld chk %ld inapp %d", tag, [SL doubleValue], [SLL doubleValue], (long)[SW state], (long)[SWL state], (long)[SEG selectedSegment], (long)[CHK state], INAPP]);
}

static void burst(NSString *tag, NSPoint a) {
    mouse(@"move", a); usleep(300000);
    mouse(@"down", a);
    for (int i = 0; i < 6; i++) { shoot([NSString stringWithFormat:@"%@_d%d", tag, i]); usleep(40000); }
    for (int i = 1; i <= 12; i++) { mouse(@"drag", NSMakePoint(a.x + 10 * i, a.y)); if (i % 3 == 0) shoot([NSString stringWithFormat:@"%@_m%d", tag, i]); }
    mouse(@"up", NSMakePoint(a.x + 120, a.y));
    for (int i = 0; i < 6; i++) { shoot([NSString stringWithFormat:@"%@_u%d", tag, i]); usleep(40000); }
    L([NSString stringWithFormat:@"VALUES %@ slider %.1f", tag, [SL doubleValue]]);
}
static void activateByClick(void) {
    NSPoint p = NSMakePoint(700, 40);
    mouse(@"move", p); usleep(100000); mouse(@"down", p); usleep(80000); mouse(@"up", p); usleep(400000);
    L([NSString stringWithFormat:@"after activate click key=%d active=%d", [WIN isKeyWindow], [NSApp isActive]]);
}
static void runPass(NSString *pass) {
    activateByClick();
    if ([pass isEqual:@"light"]) dumpTree(@"idle_slider", SL);
    __block NSPoint ks, kl;
    dispatch_sync(dispatch_get_main_queue(), ^{ ks = knob(SL); kl = knob(SLL); });
    NSRect sw = [SW convertRect:[SW bounds] toView:nil], swl = [SWL convertRect:[SWL bounds] toView:nil], sg = [SEG convertRect:[SEG bounds] toView:nil];
    NSRect pb = [PUSH convertRect:[PUSH bounds] toView:nil], cb = [CHK convertRect:[CHK bounds] toView:nil];
    NSString *(^T)(NSString *) = ^NSString *(NSString *n) { return [NSString stringWithFormat:@"%@_%@", pass, n]; };
    scene(T(@"slider"), ks, NSMakePoint(ks.x + 120, ks.y), YES);
    if ([SL doubleValue] < 41) L(@"real events did not move the slider");
    resetMain(); scene(T(@"track_click"), NSMakePoint(ks.x + 110, ks.y), NSZeroPoint, NO);
    resetMain(); burst(T(@"slider_burst"), ks);
    resetMain(); scene(T(@"sliderL"), kl, NSMakePoint(kl.x + 120, kl.y), YES);
    resetMain(); scene(T(@"switch_hold"), NSMakePoint(NSMinX(sw) + NSHeight(sw) * 0.5, NSMidY(sw)), NSZeroPoint, NO);
    resetMain(); scene(T(@"switch_drag"), NSMakePoint(NSMinX(sw) + NSHeight(sw) * 0.5, NSMidY(sw)), NSMakePoint(NSMaxX(sw) - NSHeight(sw) * 0.5, NSMidY(sw)), YES);
    resetMain(); scene(T(@"switchL_drag"), NSMakePoint(NSMinX(swl) + NSHeight(swl) * 0.5, NSMidY(swl)), NSMakePoint(NSMaxX(swl) - NSHeight(swl) * 0.5, NSMidY(swl)), YES);
    resetMain(); scene(T(@"seg_drag"), NSMakePoint(NSMinX(sg) + NSWidth(sg) / 6, NSMidY(sg)), NSMakePoint(NSMinX(sg) + NSWidth(sg) * 5 / 6, NSMidY(sg)), YES);
    resetMain(); scene(T(@"push_hold"), mid(pb), NSZeroPoint, NO);
    resetMain(); scene(T(@"check_hold"), NSMakePoint(NSMinX(cb) + 8, NSMidY(cb)), NSZeroPoint, NO);
    resetMain();
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        OUT = [[NSString stringWithUTF8String:(argc > 1 ? argv[1] : ".")] retain];
        LOG = fopen([[OUT stringByAppendingPathComponent:@"log.txt"] UTF8String], "w");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
            L(@"WATCHDOG exit"); [@"x" writeToFile:[OUT stringByAppendingPathComponent:@"quit.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil]; _exit(0);
        });
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        WIN = [[KeyWin alloc] initWithContentRect:NSMakeRect(120, 120, WW, WH) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        [WIN setHasShadow:NO]; [WIN setLevel:NSFloatingWindowLevel];
        BASE = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, WW, WH)]; [BASE setWantsLayer:YES]; [WIN setContentView:BASE];
        GRID = [[GridView alloc] initWithFrame:[BASE bounds]]; [BASE addSubview:GRID]; [GRID setHidden:YES];
        ROOT = [[NSView alloc] initWithFrame:[BASE bounds]]; [BASE addSubview:ROOT];
        [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp) handler:^NSEvent *(NSEvent *e) { L([NSString stringWithFormat:@"  EV type=%ld cc=%ld loc=%.0f,%.0f win=%ld", (long)[e type], (long)[e clickCount], [e locationInWindow].x, [e locationInWindow].y, (long)[e windowNumber]]); return e; }];
        ensureKey();
        L([NSString stringWithFormat:@"key=%d active=%d scale=%.1f appTrusted=%d os=%@", [WIN isKeyWindow], [NSApp isActive], [WIN backingScaleFactor], AXIsProcessTrusted(), [[NSProcessInfo processInfo] operatingSystemVersionString]]);
        request(@"MOUSE trust 0 0");
        NSArray *passes = @[@[@"light", @0, @0], @[@"dark", @1, @0], @[@"grid", @0, @1]];
        for (NSArray *ps in passes) {
            NSAppearance *ap = [NSAppearance appearanceNamed:([ps[1] intValue] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
            [WIN setAppearance:ap];
            [GRID setHidden:![ps[2] intValue]];
            [ap performAsCurrentDrawingAppearance:^{ [[BASE layer] setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]]; }];
            build();
            ensureKey();
            WF = [WIN frame]; SH = NSHeight([[NSScreen screens][0] frame]); WNUM = [WIN windowNumber];
            L([NSString stringWithFormat:@"PASS %@ window %.0f %.0f %.0f %.0f screenH %.0f", ps[0], NSMinX(WF), NSMinY(WF), NSWidth(WF), NSHeight(WF), SH]);
            DONE = 0;
            NSString *name = ps[0];
            [NSThread detachNewThreadWithBlock:^{ @autoreleasepool { runPass(name); DONE = 1; } }];
            while (!DONE) pump(0.03);
        }
        L(@"done");
        [@"x" writeToFile:[OUT stringByAppendingPathComponent:@"quit.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        if (LOG) fclose(LOG);
    }
    return 0;
}
