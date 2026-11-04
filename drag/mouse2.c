// mouse2: real mouse events at global top-left points.
//   down|up|drag|move X Y          one event
//   click X Y [HOLDMS]             move, press, hold, release
//   rclick X Y                     right click
//   glide X0 Y0 X1 Y1 MS [d]       eased path, one event every 8 ms (d = button held: dragged events)
//   ts                             prints wall time (s)
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/time.h>
static double now(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec + t.tv_usec / 1e6; }
static void post(CGEventType t, double x, double y, CGMouseButton b) {
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, CGPointMake(x, y), b);
    if (!e) return;
    if (t != kCGEventMouseMoved) CGEventSetIntegerValueField(e, kCGMouseEventClickState, 1);
    if (t == kCGEventLeftMouseDown || t == kCGEventLeftMouseDragged) CGEventSetDoubleValueField(e, kCGMouseEventPressure, 1.0);
    CGEventPost(kCGHIDEventTap, e); CFRelease(e);
}
int main(int c, char **v) {
    if (c < 2) return 1;
    const char *m = v[1];
    if (!strcmp(m, "ts")) { printf("%.3f\n", now()); return 0; }
    if (c < 4) return 1;
    double x = atof(v[2]), y = atof(v[3]);
    if (!strcmp(m, "glide")) {
        if (c < 7) return 1;
        double x1 = atof(v[4]), y1 = atof(v[5]), ms = atof(v[6]);
        int drag = (c > 7 && v[7][0] == 'd');
        int n = (int)(ms / 8.0); if (n < 1) n = 1;
        double t0 = now();
        for (int i = 1; i <= n; i++) {
            double f = (double)i / n;
            double e = f < 0.5 ? 2 * f * f : 1 - (-2 * f + 2) * (-2 * f + 2) / 2;
            post(drag ? kCGEventLeftMouseDragged : kCGEventMouseMoved, x + (x1 - x) * e, y + (y1 - y) * e, kCGMouseButtonLeft);
            double d = t0 + i * ms / 1000.0 / n - now(); if (d > 0) usleep((useconds_t)(d * 1e6));
        }
        printf("glide %s %.0f %.0f > %.0f %.0f %.0fms t=%.3f\n", drag ? "drag" : "move", x, y, x1, y1, ms, t0);
        return 0;
    }
    if (!strcmp(m, "click")) {
        double hold = c > 4 ? atof(v[4]) : 90;
        post(kCGEventMouseMoved, x, y, kCGMouseButtonLeft); usleep(30000);
        double t0 = now();
        post(kCGEventLeftMouseDown, x, y, kCGMouseButtonLeft); usleep((useconds_t)(hold * 1000));
        post(kCGEventLeftMouseUp, x, y, kCGMouseButtonLeft);
        printf("click %.0f %.0f hold %.0f t=%.3f\n", x, y, hold, t0); return 0;
    }
    if (!strcmp(m, "rclick")) {
        post(kCGEventMouseMoved, x, y, kCGMouseButtonLeft); usleep(30000);
        double t0 = now();
        post(kCGEventRightMouseDown, x, y, kCGMouseButtonRight); usleep(90000);
        post(kCGEventRightMouseUp, x, y, kCGMouseButtonRight);
        printf("rclick %.0f %.0f t=%.3f\n", x, y, t0); return 0;
    }
    CGEventType t = kCGEventMouseMoved;
    if (!strcmp(m, "down")) t = kCGEventLeftMouseDown; else if (!strcmp(m, "up")) t = kCGEventLeftMouseUp; else if (!strcmp(m, "drag")) t = kCGEventLeftMouseDragged;
    post(t, x, y, kCGMouseButtonLeft);
    printf("%s %.0f %.0f t=%.3f\n", m, x, y, now());
    return 0;
}
