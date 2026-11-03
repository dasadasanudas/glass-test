// Accent probe: launched once per AppleAccentColor value; logs resolved accent-driven colours (light + dark) and shoots controls.
#import <AppKit/AppKit.h>
#include <unistd.h>
static FILE *LOG = NULL;
static void L(NSString *s) { if (LOG) { fprintf(LOG, "%s\n", [s UTF8String]); fflush(LOG); } }
@interface KeyWin : NSWindow
@end
@implementation KeyWin
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end
static NSString *OUT = nil, *TAG = nil; static NSWindow *WIN = nil;
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
    for (int i = 0; i < 300 && ![[NSFileManager defaultManager] fileExistsAtPath:ack]; i++) pump(0.02);
}
static void ensureKey(void) {
    for (int i = 0; i < 40 && !([WIN isKeyWindow] && [NSApp isActive]); i++) {
        [NSApp activateIgnoringOtherApps:YES];
        if ([NSApp respondsToSelector:@selector(activate)]) [NSApp performSelector:@selector(activate)];
        [WIN makeKeyAndOrderFront:nil]; [WIN makeMainWindow]; pump(0.1);
    }
    pump(0.5);
}
static NSString *rgb(NSColor *c) { NSColor *s = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]; if (!s) return @"?"; return [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.2f", [s redComponent] * 255, [s greenComponent] * 255, [s blueComponent] * 255, [s alphaComponent]]; }
int main(int argc, const char **argv) {
    @autoreleasepool {
        OUT = [[NSString stringWithUTF8String:(argc > 1 ? argv[1] : ".")] retain];
        TAG = [[NSString stringWithUTF8String:(argc > 2 ? argv[2] : "x")] retain];
        LOG = fopen([[OUT stringByAppendingPathComponent:@"accent_log.txt"] UTF8String], "a");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{ L(@"WATCHDOG"); [@"x" writeToFile:[OUT stringByAppendingPathComponent:@"quit.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil]; _exit(0); });
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp finishLaunching];
        WIN = [[KeyWin alloc] initWithContentRect:NSMakeRect(120, 120, 640, 120) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        [WIN setHasShadow:NO]; [WIN setLevel:NSFloatingWindowLevel];
        NSView *base = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 120)]; [base setWantsLayer:YES]; [WIN setContentView:base];
        NSSwitch *sw = [[NSSwitch alloc] init]; [sw setState:1]; [sw sizeToFit]; [sw setFrameOrigin:NSMakePoint(16, 76)]; [base addSubview:sw];
        NSButton *cb = [NSButton checkboxWithTitle:@"Check" target:nil action:nil]; [cb setState:1]; [cb sizeToFit]; [cb setFrameOrigin:NSMakePoint(90, 80)]; [base addSubview:cb];
        NSButton *rb = [NSButton radioButtonWithTitle:@"Radio" target:nil action:nil]; [rb setState:1]; [rb sizeToFit]; [rb setFrameOrigin:NSMakePoint(170, 80)]; [base addSubview:rb];
        NSSegmentedControl *sg = [NSSegmentedControl segmentedControlWithLabels:@[@"One", @"Two", @"Three"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil]; [sg setSelectedSegment:0]; [sg sizeToFit]; [sg setFrameOrigin:NSMakePoint(250, 76)]; [base addSubview:sg];
        NSButton *db = [NSButton buttonWithTitle:@"Default" target:nil action:nil]; [db setKeyEquivalent:@"\r"]; [db sizeToFit]; [db setFrameOrigin:NSMakePoint(420, 76)]; [base addSubview:db];
        NSSlider *sl = [NSSlider sliderWithValue:60 minValue:0 maxValue:100 target:nil action:nil]; [sl setFrame:NSMakeRect(16, 30, 300, 20)]; [base addSubview:sl];
        NSTextField *tf = [NSTextField textFieldWithString:@"Selected text"]; [tf setFrame:NSMakeRect(340, 28, 180, 24)]; [base addSubview:tf];
        ensureKey();
        [WIN makeFirstResponder:tf]; [[tf currentEditor] setSelectedRange:NSMakeRange(0, 8)]; pump(0.3);
        NSArray *names = @[@"controlAccentColor", @"selectedContentBackgroundColor", @"unemphasizedSelectedContentBackgroundColor", @"keyboardFocusIndicatorColor", @"selectedTextBackgroundColor", @"selectedControlColor", @"alternateSelectedControlColor", @"linkColor", @"systemBlueColor", @"systemPinkColor", @"systemPurpleColor", @"systemRedColor", @"systemOrangeColor", @"systemYellowColor", @"systemGreenColor", @"systemGrayColor", @"findHighlightColor", @"windowBackgroundColor", @"controlBackgroundColor"];
        for (int dark = 0; dark < 2; dark++) {
            NSAppearance *ap = [NSAppearance appearanceNamed:(dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
            [WIN setAppearance:ap];
            [ap performAsCurrentDrawingAppearance:^{ [[base layer] setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]]; }];
            ensureKey(); pump(0.4);
            __block NSMutableString *s = [NSMutableString stringWithFormat:@"ACCENT %@ %@", TAG, dark ? @"dark" : @"light"];
            [ap performAsCurrentDrawingAppearance:^{ for (NSString *n in names) if ([NSColor respondsToSelector:NSSelectorFromString(n)]) [s appendFormat:@" | %@ %@", n, rgb([NSColor performSelector:NSSelectorFromString(n)])]; }];
            [s appendFormat:@" | AppleAccentColor %@ | AppleHighlightColor %@", [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleAccentColor"], [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleHighlightColor"]];
            L(s);
            request([NSString stringWithFormat:@"SHOT accent_%@_%@ %ld", TAG, dark ? @"dark" : @"light", (long)[WIN windowNumber]]);
        }
        L([NSString stringWithFormat:@"FRAMES %@ switch %.0f,%.0f,%.0f,%.0f check %.0f,%.0f radio %.0f,%.0f seg %.0f,%.0f,%.0f,%.0f default %.0f,%.0f,%.0f,%.0f", TAG, NSMinX([sw frame]), 120 - NSMaxY([sw frame]), NSWidth([sw frame]), NSHeight([sw frame]), NSMinX([cb frame]), 120 - NSMaxY([cb frame]), NSMinX([rb frame]), 120 - NSMaxY([rb frame]), NSMinX([sg frame]), 120 - NSMaxY([sg frame]), NSWidth([sg frame]), NSHeight([sg frame]), NSMinX([db frame]), 120 - NSMaxY([db frame]), NSWidth([db frame]), NSHeight([db frame])]);
        [@"x" writeToFile:[OUT stringByAppendingPathComponent:@"quit.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        if (LOG) fclose(LOG);
    }
    return 0;
}
