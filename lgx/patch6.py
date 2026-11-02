# Run 6: reuses the run-5 edits (patch5.py) with a new scene list and one extra texture dump.
# New: small shapes over the test pattern (clear/dock/regular/lens), tall shapes, lens ramp texture (256x1).
import sys
src = open('lgx/patch5.py').read()
src = src.replace('if ([lb rangeOfString:@"noise"].location == NSNotFound) continue;',
                  'if ([lb rangeOfString:@"noise"].location == NSNotFound && !([t height] == 1 && [t width] <= 4096)) continue;')
NEW_MAIN = r'''  // ===== run 6 =====
  gLight = 0;
  scene(@"p1_v11", pat1, CGSizeMake(700, 200), gfp, 24, 11, 1, strategy);
  scene(@"q64_v11", pat1, CGSizeMake(700, 200), CGRectMake(100, 68, 64, 64), 14.4, 11, 1, strategy);
  setDark(1);
  scene(@"p1d_v11", pat1, CGSizeMake(700, 200), gfp, 24, 11, 1, strategy);
  setDark(0);
  gLight = 1;
  { double sq[] = {32, 44, 64, 100, 164};
    long vv[] = {2, 3, 0, 11};
    for (int j = 0; j < 4; j++) {
      for (int i = 0; i < 5; i++) { double w = sq[i];
        scene([NSString stringWithFormat:@"sq%g_v%ld", w, vv[j]], pat1, CGSizeMake(700, 200), CGRectMake(100, floor((200 - w) / 2), w, w), MIN(0.225 * w, w / 2), vv[j], 1, strategy); }
      scene([NSString stringWithFormat:@"pill120_v%ld", vv[j]], pat1, CGSizeMake(700, 200), CGRectMake(100, 78, 120, 44), 22, vv[j], 1, strategy);
      scene([NSString stringWithFormat:@"circ64_v%ld", vv[j]], pat1, CGSizeMake(700, 200), CGRectMake(100, 68, 64, 64), 32, vv[j], 1, strategy);
    } }
  { double th[] = {170, 180, 200, 220, 260, 300, 360};
    long vv[] = {0, 2, 3};
    for (int j = 0; j < 3; j++) for (int i = 0; i < 7; i++) { double H = th[i];
      scene([NSString stringWithFormat:@"tall_h%g_v%ld", H, vv[j]], pat1, CGSizeMake(700, 440), CGRectMake(50, floor((440 - H) / 2), 600, H), 16, vv[j], 1, strategy); }
    scene(@"tall_w200_h300_v0", pat1, CGSizeMake(700, 440), CGRectMake(250, 70, 200, 300), 16, 0, 1, strategy);
    scene(@"tall_w300_h170_v0", pat1, CGSizeMake(700, 440), CGRectMake(200, 135, 300, 170), 16, 0, 1, strategy);
  }
  gLight = 0;
  LF(@"DONE");
  return 0;
} }
'''
i = src.index("MAIN = r'''")
j = src.index("'''", i + len("MAIN = r'''")) + 3
src = src[:i] + 'MAIN = r' + "'''" + NEW_MAIN + "'''" + src[j:]
exec(compile(src, 'patch5_run6', 'exec'))
