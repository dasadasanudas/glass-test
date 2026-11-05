// axdock PID: prints the Dock's accessibility tree two levels deep, one line per element:
// depth, role, title, x, y, w, h (global top-left points). Used to read every Dock item's frame per sweep step.
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
static void dump(AXUIElementRef e, int depth) {
    CFArrayRef kids = NULL;
    if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, (CFTypeRef *)&kids) != kAXErrorSuccess || !kids) return;
    for (CFIndex i = 0; i < CFArrayGetCount(kids); i++) {
        AXUIElementRef k = (AXUIElementRef)CFArrayGetValueAtIndex(kids, i);
        CFTypeRef role = NULL, title = NULL, pos = NULL, size = NULL;
        AXUIElementCopyAttributeValue(k, kAXRoleAttribute, &role);
        AXUIElementCopyAttributeValue(k, kAXTitleAttribute, &title);
        CGPoint p = {0, 0}; CGSize s = {0, 0};
        if (AXUIElementCopyAttributeValue(k, kAXPositionAttribute, &pos) == kAXErrorSuccess && pos) { AXValueGetValue((AXValueRef)pos, kAXValueCGPointType, &p); CFRelease(pos); }
        if (AXUIElementCopyAttributeValue(k, kAXSizeAttribute, &size) == kAXErrorSuccess && size) { AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &s); CFRelease(size); }
        char rb[64] = "", tb[160] = "";
        if (role) { if (CFGetTypeID(role) == CFStringGetTypeID()) CFStringGetCString((CFStringRef)role, rb, sizeof rb, kCFStringEncodingUTF8); CFRelease(role); }
        if (title) { if (CFGetTypeID(title) == CFStringGetTypeID()) CFStringGetCString((CFStringRef)title, tb, sizeof tb, kCFStringEncodingUTF8); CFRelease(title); }
        printf("%d\t%s\t%s\t%.1f\t%.1f\t%.1f\t%.1f\n", depth, rb, tb, p.x, p.y, s.width, s.height);
        if (depth < 1) dump(k, depth + 1);
    }
    CFRelease(kids);
}
int main(int c, char **v) {
    if (c < 2) return 1;
    AXUIElementRef app = AXUIElementCreateApplication(atoi(v[1]));
    dump(app, 0);
    CFRelease(app);
    return 0;
}
