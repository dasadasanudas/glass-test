// mouse down|drag|up|move|trust X Y : posts a real left-button mouse event at global top-left coordinates
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int c, char **v) {
    if (c < 4) return 1;
    if (!strcmp(v[1], "trust")) { printf("helper trusted=%d\n", AXIsProcessTrusted()); return 0; }
    CGPoint p = CGPointMake(atof(v[2]), atof(v[3]));
    CGEventType t = kCGEventMouseMoved;
    if (!strcmp(v[1], "down")) t = kCGEventLeftMouseDown; else if (!strcmp(v[1], "up")) t = kCGEventLeftMouseUp; else if (!strcmp(v[1], "drag")) t = kCGEventLeftMouseDragged;
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, kCGMouseButtonLeft);
    if (!e) { printf("no event\n"); return 2; }
    if (t != kCGEventMouseMoved) CGEventSetIntegerValueField(e, kCGMouseEventClickState, 1);
    if (t == kCGEventLeftMouseDown || t == kCGEventLeftMouseDragged) CGEventSetDoubleValueField(e, kCGMouseEventPressure, 1.0);
    CGEventPost(kCGHIDEventTap, e); CFRelease(e);
    printf("%s %.1f %.1f\n", v[1], p.x, p.y);
    return 0;
}
