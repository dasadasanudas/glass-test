// axtree PID [MAXDEPTH]: one process's accessibility tree, one tab-separated line per element:
// depth, role, subrole, title, description, value, identifier, enabled, cmdchar, cmdmods, cmdglyph, mark, x, y, w, h
// (global top-left points). Menu items carry their shortcut (cmdmods: 0 = cmd only, +1 shift, +2 option, +4 control, +8 no cmd).
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
static int maxd = 12, count = 0;
static void str(CFTypeRef v, char *b, size_t n) {
  b[0] = 0; if (!v) return;
  CFTypeID t = CFGetTypeID(v);
  if (t == CFStringGetTypeID()) CFStringGetCString((CFStringRef)v, b, n, kCFStringEncodingUTF8);
  else if (t == CFNumberGetTypeID()) { double d = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d); snprintf(b, n, "%g", d); }
  else if (t == CFBooleanGetTypeID()) snprintf(b, n, "%d", CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0);
  for (char *q = b; *q; q++) if (*q == '\t' || *q == '\n' || *q == '\r') *q = ' ';
}
static void attr(AXUIElementRef e, CFStringRef a, char *b, size_t n) { CFTypeRef v = NULL; b[0] = 0; if (AXUIElementCopyAttributeValue(e, a, &v) == kAXErrorSuccess && v) { str(v, b, n); CFRelease(v); } }
static void dump(AXUIElementRef e, int d) {
  if (d > maxd || count > 8000) return; count++;
  char role[64], sub[64], title[240], desc[240], val[240], ident[160], en[8], ch[16], mods[16], gl[16], mk[16];
  attr(e, kAXRoleAttribute, role, sizeof role); attr(e, kAXSubroleAttribute, sub, sizeof sub); attr(e, kAXTitleAttribute, title, sizeof title);
  attr(e, kAXDescriptionAttribute, desc, sizeof desc); attr(e, kAXValueAttribute, val, sizeof val); attr(e, CFSTR("AXIdentifier"), ident, sizeof ident);
  attr(e, kAXEnabledAttribute, en, sizeof en); attr(e, kAXMenuItemCmdCharAttribute, ch, sizeof ch); attr(e, kAXMenuItemCmdModifiersAttribute, mods, sizeof mods);
  attr(e, kAXMenuItemCmdGlyphAttribute, gl, sizeof gl); attr(e, kAXMenuItemMarkCharAttribute, mk, sizeof mk);
  CGPoint p = {0, 0}; CGSize s = {0, 0}; CFTypeRef pos = NULL, size = NULL;
  if (AXUIElementCopyAttributeValue(e, kAXPositionAttribute, &pos) == kAXErrorSuccess && pos) { AXValueGetValue((AXValueRef)pos, kAXValueCGPointType, &p); CFRelease(pos); }
  if (AXUIElementCopyAttributeValue(e, kAXSizeAttribute, &size) == kAXErrorSuccess && size) { AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &s); CFRelease(size); }
  printf("%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\t%.1f\n", d, role, sub, title, desc, val, ident, en, ch, mods, gl, mk, p.x, p.y, s.width, s.height);
  CFArrayRef kids = NULL;
  if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, (CFTypeRef *)&kids) == kAXErrorSuccess && kids) {
    for (CFIndex i = 0; i < CFArrayGetCount(kids); i++) dump((AXUIElementRef)CFArrayGetValueAtIndex(kids, i), d + 1);
    CFRelease(kids);
  }
}
int main(int c, char **v) {
  if (c < 2) return 1;
  if (c > 2) maxd = atoi(v[2]);
  AXUIElementRef app = AXUIElementCreateApplication(atoi(v[1]));
  AXUIElementSetMessagingTimeout(app, 3.0);
  dump(app, 0); CFRelease(app); return 0;
}
