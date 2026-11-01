// glass variant probe (Nov 1): Apple-runtime introspection plus configured-input sweep.
// Records configured CoreAnimation layer/filter properties only. The runner GPU is
// paravirtual, so nothing here is a physical-Mac pixel or GPU-uniform measurement.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <spawn.h>
#import <sys/wait.h>
#import <fcntl.h>
#import <string.h>
#import <time.h>
#import <dlfcn.h>
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
extern char **environ;

static CFTypeID (*pCGColorGetTypeID)(void);
static size_t (*pCGColorGetNumberOfComponents)(CGColorRef);
static const CGFloat*(*pCGColorGetComponents)(CGColorRef);
static CGColorSpaceRef (*pCGColorGetColorSpace)(CGColorRef);
static CFStringRef (*pCGColorSpaceCopyName)(CGColorSpaceRef);
static CFArrayRef (*pCGWindowListCopyWindowInfo)(uint32_t,uint32_t);
static void loadCG(void){
  pCGColorGetTypeID=(CFTypeID(*)(void))dlsym(RTLD_DEFAULT,"CGColorGetTypeID");
  pCGColorGetNumberOfComponents=(size_t(*)(CGColorRef))dlsym(RTLD_DEFAULT,"CGColorGetNumberOfComponents");
  pCGColorGetComponents=(const CGFloat*(*)(CGColorRef))dlsym(RTLD_DEFAULT,"CGColorGetComponents");
  pCGColorGetColorSpace=(CGColorSpaceRef(*)(CGColorRef))dlsym(RTLD_DEFAULT,"CGColorGetColorSpace");
  pCGColorSpaceCopyName=(CFStringRef(*)(CGColorSpaceRef))dlsym(RTLD_DEFAULT,"CGColorSpaceCopyName");
  pCGWindowListCopyWindowInfo=(CFArrayRef(*)(uint32_t,uint32_t))dlsym(RTLD_DEFAULT,"CGWindowListCopyWindowInfo");
}
static double nowS(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (double)t.tv_sec+(double)t.tv_nsec*1e-9;}
static void pump(double s){NSDate*e=[NSDate dateWithTimeIntervalSinceNow:s];while(e.timeIntervalSinceNow>0){NSEvent*n=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:.02] inMode:NSDefaultRunLoopMode dequeue:YES];if(n)[NSApp sendEvent:n];}}
static void P(NSString*s){if(!s)s=@"<null>";s=[[s stringByReplacingOccurrencesOfString:@"\n" withString:@" | "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];const char*u=s.UTF8String;fputs(u?u:"<utf8-null>",stdout);fputc('\n',stdout);}

static NSString*D(id v){
  if(!v)return @"<nil>";
  @try{
    NSString*cn=NSStringFromClass([v class]);
    if([cn isEqualToString:@"__NSCFType"]){
      CFTypeRef cf=(__bridge CFTypeRef)v;
      if(pCGColorGetTypeID&&pCGColorGetNumberOfComponents&&pCGColorGetComponents&&pCGColorGetColorSpace&&pCGColorSpaceCopyName&&CFGetTypeID(cf)==pCGColorGetTypeID()){
        CGColorRef c=(CGColorRef)cf;size_t n=pCGColorGetNumberOfComponents(c);const CGFloat*k=pCGColorGetComponents(c);
        NSMutableString*s=[NSMutableString stringWithString:@"CGColor["];
        for(size_t i=0;k&&i<n;i++)[s appendFormat:@"%@%.9g",i?@",":@"",(double)k[i]];
        CGColorSpaceRef sp=pCGColorGetColorSpace(c);CFStringRef nm=sp?pCGColorSpaceCopyName(sp):NULL;
        [s appendFormat:@"] space=%@",nm?(__bridge NSString*)nm:@"?"];if(nm)CFRelease(nm);
        return s;
      }
    }
    if([v isKindOfClass:[NSNumber class]]){NSNumber*n=v;return [NSString stringWithFormat:@"num(%s) %.17g",n.objCType,n.doubleValue];}
    if([v isKindOfClass:[NSValue class]]){
      NSValue*nv=v;const char*t=nv.objCType;NSUInteger sz=0,al=0;NSGetSizeAndAlignment(t,&sz,&al);
      NSMutableString*s=[NSMutableString stringWithFormat:@"val(%s,%lu) %@ hex=",t,(unsigned long)sz,nv.description];
      if(sz>0&&sz<=512){unsigned char b[512];[nv getValue:b size:sz];for(NSUInteger i=0;i<sz;i++)[s appendFormat:@"%02x",b[i]];}
      return s;
    }
    if([v isKindOfClass:[NSString class]])return [@"str " stringByAppendingString:(NSString*)v];
    if([v isKindOfClass:[NSArray class]]){NSArray*a=v;NSMutableString*s=[NSMutableString stringWithFormat:@"array[%lu](",(unsigned long)a.count];for(id x in a)[s appendFormat:@"%@; ",D(x)];[s appendString:@")"];return s;}
    if([v isKindOfClass:[NSColor class]]){NSColor*c=[(NSColor*)v colorUsingColorSpace:NSColorSpace.extendedSRGBColorSpace];if(c)return [NSString stringWithFormat:@"NSColor[%.9g,%.9g,%.9g,%.9g] %@",c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent,[v description]];}
    return [NSString stringWithFormat:@"<%@> %@",cn,[v description]];
  }@catch(NSException*e){return [NSString stringWithFormat:@"<desc-exception %@>",e.reason];}
}

static BOOL skipName(NSString*n){
  for(NSString*s in @[@"superlayer",@"delegate",@"sublayers",@"layer",@"window",@"superview",@"subviews",@"nextResponder",@"menu",@"enclosingScrollView",@"constraints",@"trackingAreas",@"gestureRecognizers",@"registeredDraggedTypes",@"layoutGuides",@"subtreeDescription"])if([n isEqualToString:s])return YES;
  return NO;
}
static void dumpProps(id o,Class stop,NSString*pre){
  NSMutableSet*seen=[NSMutableSet set];
  for(Class c=[o class];c&&c!=stop;c=class_getSuperclass(c)){
    unsigned int n=0;objc_property_t*ps=class_copyPropertyList(c,&n);
    for(unsigned int i=0;i<n;i++){
      const char*pn=property_getName(ps[i]);if(!pn)continue;
      NSString*name=[NSString stringWithUTF8String:pn];if(!name||[seen containsObject:name]||skipName(name))continue;[seen addObject:name];
      const char*at=property_getAttributes(ps[i]);
      if(!at||at[0]!='T'||at[1]=='^'||at[1]=='*'||at[1]=='?'||(at[1]=='@'&&at[2]=='?')){P([NSString stringWithFormat:@"%@P %@ = <skipped> [%s]",pre,name,at?at:""]);continue;}
      NSString*val;@try{val=D([o valueForKey:name]);}@catch(NSException*e){val=[NSString stringWithFormat:@"<exception %@>",e.reason];}
      P([NSString stringWithFormat:@"%@P %@ = %@ [%s] {%s}",pre,name,val,at,class_getName(c)]);
    }
    free(ps);
  }
}

static void dumpFilter(id f,NSString*pre){
  id type=nil,name=nil,en=nil;
  @try{type=[f valueForKey:@"type"];}@catch(NSException*x){type=nil;}
  @try{name=[f valueForKey:@"name"];}@catch(NSException*x){name=nil;}
  @try{en=[f valueForKey:@"enabled"];}@catch(NSException*x){en=nil;}
  P([NSString stringWithFormat:@"%@FILTER class=%@ type=%@ name=%@ enabled=%@",pre,NSStringFromClass([f class]),D(type),D(name),D(en)]);
  NSMutableArray*keys=[NSMutableArray array];
  @try{id ks=[f valueForKey:@"inputKeys"];if([ks isKindOfClass:[NSArray class]])[keys addObjectsFromArray:(NSArray*)ks];}@catch(NSException*x){P([NSString stringWithFormat:@"%@  INPUT_KEYS_EXCEPTION %@",pre,x.reason]);}
  for(NSString*k in @[@"inputBackdropAware",@"inputClamp",@"inputClampPreserveHue",@"inputColorMatrix",@"inputReversed",@"inputNormalizeEdges",@"inputAmount",@"inputRadius"])if(![keys containsObject:k])[keys addObject:k];
  P([NSString stringWithFormat:@"%@  INPUT_COUNT %lu",pre,(unsigned long)keys.count]);
  for(id k in keys){if(![k isKindOfClass:[NSString class]])continue;NSString*v;@try{v=D([f valueForKey:(NSString*)k]);}@catch(NSException*x){v=[NSString stringWithFormat:@"<exception %@>",x.reason];}P([NSString stringWithFormat:@"%@  IN %@ = %@",pre,k,v]);}
}

static int gLayers=0;
static NSString*T3(CATransform3D t){return [NSString stringWithFormat:@"[%g %g %g %g; %g %g %g %g; %g %g %g %g; %g %g %g %g]",t.m11,t.m12,t.m13,t.m14,t.m21,t.m22,t.m23,t.m24,t.m31,t.m32,t.m33,t.m34,t.m41,t.m42,t.m43,t.m44];}
static BOOL wantProps(NSString*c){return !([c hasPrefix:@"NS"]||[c hasPrefix:@"_TtCC6AppKit"]||[c isEqualToString:@"CALayer"]);}
static void walk(CALayer*l,NSString*path,int d){
  if(!l||d>30||gLayers>700)return;gLayers++;
  NSString*c=NSStringFromClass([l class]);NSString*pre=[NSString stringWithFormat:@"  [%@] ",path];
  P([NSString stringWithFormat:@"LAYER path=%@ depth=%d class=%@ frame=%@ bounds=%@ opacity=%.9g hidden=%d name=%@ z=%g masks=%d corner=%g groupOpacity=%d sublayers=%lu",path,d,c,NSStringFromRect(NSRectFromCGRect(l.frame)),NSStringFromRect(NSRectFromCGRect(l.bounds)),l.opacity,(int)l.hidden,l.name?l.name:@"<nil>",l.zPosition,(int)l.masksToBounds,l.cornerRadius,(int)l.allowsGroupOpacity,(unsigned long)l.sublayers.count]);
  if(l.compositingFilter)P([NSString stringWithFormat:@"%@compositingFilter = %@",pre,D(l.compositingFilter)]);
  if(l.backgroundColor)P([NSString stringWithFormat:@"%@backgroundColor = %@",pre,D((__bridge id)l.backgroundColor)]);
  if(l.contents)P([NSString stringWithFormat:@"%@contents = <%@>",pre,NSStringFromClass([l.contents class])]);
  if(l.mask)P([NSString stringWithFormat:@"%@mask = <%@> frame=%@",pre,NSStringFromClass([l.mask class]),NSStringFromRect(NSRectFromCGRect(l.mask.frame))]);
  if(!CATransform3DIsIdentity(l.transform))P([NSString stringWithFormat:@"%@transform = %@",pre,T3(l.transform)]);
  if(!CATransform3DIsIdentity(l.sublayerTransform))P([NSString stringWithFormat:@"%@sublayerTransform = %@",pre,T3(l.sublayerTransform)]);
  if(wantProps(c))dumpProps(l,[CALayer class],pre);
  id e=nil;
  if([l respondsToSelector:NSSelectorFromString(@"effect")]){@try{e=[l valueForKey:@"effect"];}@catch(NSException*x){e=nil;}}
  if(e){P([NSString stringWithFormat:@"%@EFFECT class=%@",pre,NSStringFromClass([e class])]);dumpProps(e,[NSObject class],[pre stringByAppendingString:@"E "]);}
  for(id f in l.filters)dumpFilter(f,pre);
  for(id f in l.backgroundFilters){P([pre stringByAppendingString:@"BACKGROUND_FILTER_FOLLOWS"]);dumpFilter(f,pre);}
  NSUInteger i=0;for(CALayer*s in l.sublayers){walk(s,[NSString stringWithFormat:@"%@.%lu",path,(unsigned long)i],d+1);i++;}
}

static void dumpClass(Class c){
  if(!c)return;
  Class sup=class_getSuperclass(c);const char*im=class_getImageName(c);
  P([NSString stringWithFormat:@"CLASS %s super=%s image=%s",class_getName(c),sup?class_getName(sup):"-",im?im:"?"]);
  unsigned int n=0;
  Ivar*iv=class_copyIvarList(c,&n);for(unsigned int i=0;i<n;i++){const char*t=ivar_getTypeEncoding(iv[i]);P([NSString stringWithFormat:@"  IVAR %s %s off=%ld",ivar_getName(iv[i])?:"?",t?t:"",(long)ivar_getOffset(iv[i])]);}free(iv);
  objc_property_t*ps=class_copyPropertyList(c,&n);for(unsigned int i=0;i<n;i++){const char*a=property_getAttributes(ps[i]);P([NSString stringWithFormat:@"  PROP %s %s",property_getName(ps[i]),a?a:""]);}free(ps);
  Method*ms=class_copyMethodList(c,&n);for(unsigned int i=0;i<n;i++){const char*t=method_getTypeEncoding(ms[i]);P([NSString stringWithFormat:@"  METH -%s %s",sel_getName(method_getName(ms[i])),t?t:""]);}free(ms);
  ms=class_copyMethodList(object_getClass((id)c),&n);for(unsigned int i=0;i<n;i++){const char*t=method_getTypeEncoding(ms[i]);P([NSString stringWithFormat:@"  METH +%s %s",sel_getName(method_getName(ms[i])),t?t:""]);}free(ms);
}

static NSArray*setterKeys(Class c,BOOL integers){
  NSMutableArray*keys=[NSMutableArray array];
  for(Class k=c;k&&k!=[NSView class];k=class_getSuperclass(k)){
    unsigned int n=0;Method*ms=class_copyMethodList(k,&n);
    for(unsigned int i=0;i<n;i++){
      NSString*s=NSStringFromSelector(method_getName(ms[i]));
      if(![s hasPrefix:@"set"]||![s hasSuffix:@":"]||[s componentsSeparatedByString:@":"].count!=2||s.length<5)continue;
      char at[64];memset(at,0,sizeof at);method_getArgumentType(ms[i],2,at,sizeof at);
      BOOL isInt=(at[0]=='q'||at[0]=='Q'||at[0]=='i'||at[0]=='I'||at[0]=='l'||at[0]=='L'||at[0]=='c'||at[0]=='C'||at[0]=='B'||at[0]=='s'||at[0]=='S');
      BOOL isReal=(at[0]=='d'||at[0]=='f');
      if(integers?!isInt:!isReal)continue;
      NSString*body=[s substringWithRange:NSMakeRange(3,s.length-4)];
      NSString*key=[body hasPrefix:@"_"]?body:[[[body substringToIndex:1] lowercaseString] stringByAppendingString:[body substringFromIndex:1]];
      [keys addObject:@[key,[NSString stringWithUTF8String:at],[NSString stringWithUTF8String:class_getName(k)]]];
    }
    free(ms);
  }
  return keys;
}

@interface GlassProbePatternView:NSView @end
@implementation GlassProbePatternView
-(void)drawRect:(NSRect)r{[NSColor.whiteColor setFill];NSRectFill(self.bounds);for(int x=0;x<800;x+=12){[NSColor.blackColor setFill];NSRectFill(NSMakeRect(x,0,3,500));}for(int y=25;y<500;y+=60){[[NSColor colorWithCalibratedHue:y/500.0 saturation:1 brightness:.9 alpha:1] setFill];NSRectFill(NSMakeRect(0,y,800,7));}}
@end

static NSWindow*gW;static NSView*gRoot;static NSView*gBox;static Class gG;static NSAppearance*gAp;static int gCfg=0;
static void setupWindow(int dark){
  [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];[NSApp finishLaunching];
  gW=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,800,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  GlassProbePatternView*r=[[GlassProbePatternView alloc]initWithFrame:NSMakeRect(0,0,800,500)];r.wantsLayer=YES;gW.contentView=r;gRoot=r;
  gG=NSClassFromString(@"NSGlassEffectView");Class C=NSClassFromString(@"NSGlassEffectContainerView");
  gAp=[NSAppearance appearanceNamed:dark?NSAppearanceNameDarkAqua:NSAppearanceNameAqua];gW.appearance=gAp;r.appearance=gAp;
  gBox=C?[[C alloc]initWithFrame:r.bounds]:r;if(gBox!=r){gBox.appearance=gAp;[r addSubview:gBox];}
  [NSApp activateIgnoringOtherApps:YES];[gW makeKeyAndOrderFront:nil];pump(1.2);
}
static NSString*gFixKey=nil;static long gFixVal=0;
static BOOL runCfg(int gw,int gh,double radius,int style,NSString*key,long value,BOOL content,NSColor*tint,double wait){
  NSView*g=[[gG alloc]initWithFrame:NSMakeRect((800-gw)/2.0,(500-gh)/2.0,gw,gh)];g.appearance=gAp;[gBox addSubview:g];
  BOOL ok=YES;NSMutableString*err=[NSMutableString string];
  @try{[g setValue:@(radius) forKey:@"cornerRadius"];[g setValue:@(style) forKey:@"style"];}@catch(NSException*x){ok=NO;[err appendFormat:@" base:%@",x.reason];}
  if(content){NSView*cv=[[NSView alloc]initWithFrame:NSMakeRect(0,0,gw,gh)];NSTextField*t=[NSTextField labelWithString:@"Liquid Glass Aa 123"];t.font=[NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];t.frame=NSMakeRect(16,(gh-28)/2.0,gw-32,28);[cv addSubview:t];@try{[g setValue:cv forKey:@"contentView"];}@catch(NSException*x){[err appendFormat:@" content:%@",x.reason];}}
  if(tint){@try{[g setValue:tint forKey:@"tintColor"];}@catch(NSException*x){[err appendFormat:@" tint:%@",x.reason];}}
  id fixback=nil;
  if(gFixKey){@try{[g setValue:@(gFixVal) forKey:gFixKey];fixback=[g valueForKey:gFixKey];}@catch(NSException*x){[err appendFormat:@" fix:%@",x.reason];}}
  id readback=nil;
  if(key){@try{[g setValue:@(value) forKey:key];readback=[g valueForKey:key];}@catch(NSException*x){ok=NO;[err appendFormat:@" key:%@",x.reason];}}
  [NSApp activateIgnoringOtherApps:YES];[gW makeKeyAndOrderFront:nil];
  pump(wait);gCfg++;
  P([NSString stringWithFormat:@"BEGIN_CFG idx=%d fix=%@:%ld>%@ size=%dx%d radius=%g style=%d key=%@ value=%ld readback=%@ content=%d tint=%@ ok=%d err=%@ isKey=%d isMain=%d effective=%@ RT=%d",gCfg,gFixKey?gFixKey:@"-",gFixVal,D(fixback),gw,gh,radius,style,key?key:@"-",value,D(readback),(int)content,tint?D(tint):@"-",(int)ok,err,(int)gW.isKeyWindow,(int)gW.isMainWindow,g.effectiveAppearance.name,(int)NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency]);
  gLayers=0;walk(gRoot.layer,@"0",0);
  P(@"END_CFG");fflush(stdout);
  [g removeFromSuperview];pump(0.05);
  return ok;
}

static void sectionStrings(const struct mach_header_64*h,const char*seg,const char*sect,NSString*label,BOOL filter){
  unsigned long size=0;uint8_t*p=getsectiondata(h,seg,sect,&size);
  P([NSString stringWithFormat:@"SECTION %@ %s,%s size=%lu",label,seg,sect,size]);
  if(!p||!size)return;
  unsigned long i=0;int printed=0;
  while(i<size&&printed<20000){
    unsigned long j=i;while(j<size&&p[j])j++;
    if(j>i&&j-i<400){
      NSString*s=[[NSString alloc]initWithBytes:p+i length:j-i encoding:NSUTF8StringEncoding];
      if(s&&(!filter||[s rangeOfString:@"lass" options:NSCaseInsensitiveSearch].location!=NSNotFound||[s rangeOfString:@"refract" options:NSCaseInsensitiveSearch].location!=NSNotFound||[s rangeOfString:@"lensing" options:NSCaseInsensitiveSearch].location!=NSNotFound||[s rangeOfString:@"variant" options:NSCaseInsensitiveSearch].location!=NSNotFound||[s rangeOfString:@"dock" options:NSCaseInsensitiveSearch].location!=NSNotFound)){P([@"  S " stringByAppendingString:s]);printed++;}
    }
    i=j+1;
  }
}

static void runIntro(void){
  id<MTLDevice>dev=MTLCreateSystemDefaultDevice();
  P([NSString stringWithFormat:@"BEGIN_INTRO OS=%@ METAL=%@",NSProcessInfo.processInfo.operatingSystemVersionString,dev?dev.name:@"<nil>"]);
  setupWindow(0);
  NSScreen*sc=NSScreen.mainScreen;P([NSString stringWithFormat:@"SCREEN frame=%@ visible=%@ scale=%g",NSStringFromRect(sc.frame),NSStringFromRect(sc.visibleFrame),sc.backingScaleFactor]);
  CFArrayRef wl=pCGWindowListCopyWindowInfo?pCGWindowListCopyWindowInfo(0,0):NULL;
  if(wl){for(NSDictionary*d in (__bridge NSArray*)wl){if(![d isKindOfClass:[NSDictionary class]])continue;NSString*owner=d[@"kCGWindowOwnerName"];if(![owner isKindOfClass:[NSString class]])continue;if([owner isEqualToString:@"Dock"]||[owner isEqualToString:@"WindowManager"]||[owner isEqualToString:@"Control Center"]||[owner isEqualToString:@"SystemUIServer"]||[owner isEqualToString:@"Window Server"])P([NSString stringWithFormat:@"WINDOW owner=%@ name=%@ layer=%@ alpha=%@ onscreen=%@ bounds=%@",owner,d[@"kCGWindowName"],d[@"kCGWindowLayer"],d[@"kCGWindowAlpha"],d[@"kCGWindowIsOnscreen"],d[@"kCGWindowBounds"]]);}CFRelease(wl);}else P(@"WINDOW_LIST_UNAVAILABLE");
  NSMutableArray*names=[NSMutableArray array];
  unsigned int cnt=0;__unsafe_unretained Class*all=objc_copyClassList(&cnt);
  for(unsigned int i=0;i<cnt;i++){const char*nm=class_getName(all[i]);if(!nm)continue;const char*im=class_getImageName(all[i]);
    if(strcasestr(nm,"glass")||strncmp(nm,"CASDF",5)==0||strcasestr(nm,"backdrop")||strcasestr(nm,"portal")){P([NSString stringWithFormat:@"GLASSCLASS %s image=%s",nm,im?im:"?"]);
      if(strcasestr(nm,"glass")||strncmp(nm,"CASDF",5)==0||!strcmp(nm,"CABackdropLayer")||!strcmp(nm,"CAPortalLayer"))[names addObject:[NSString stringWithUTF8String:nm]];}}
  free(all);
  for(NSString*n in names)dumpClass(NSClassFromString(n));
  dumpClass(NSClassFromString(@"CAFilter"));
  Class CF=NSClassFromString(@"CAFilter");
  if([CF respondsToSelector:NSSelectorFromString(@"filterTypes")]){@try{P([@"FILTER_TYPES " stringByAppendingString:D([CF performSelector:NSSelectorFromString(@"filterTypes")])]);}@catch(NSException*x){P(@"FILTER_TYPES exception");}}
  for(NSString*t in @[@"glassBackground",@"glassForeground",@"vibrantColorMatrix",@"displacementMap",@"variableBlur",@"gaussianBlur",@"colorMatrix"]){
    id f=nil;@try{f=[CF performSelector:NSSelectorFromString(@"filterWithType:") withObject:t];}@catch(NSException*x){f=nil;}
    P([@"DEFAULT_FILTER " stringByAppendingString:t]);if(f)dumpFilter(f,@"  ");
  }
  for(NSArray*k in setterKeys(gG,YES))P([NSString stringWithFormat:@"INT_SETTER %@ type=%@ class=%@",k[0],k[1],k[2]]);
  for(NSArray*k in setterKeys(gG,NO))P([NSString stringWithFormat:@"REAL_SETTER %@ type=%@ class=%@",k[0],k[1],k[2]]);
  NSView*g=[[gG alloc]initWithFrame:NSMakeRect(100,214,600,72)];g.appearance=gAp;[gBox addSubview:g];pump(0.8);
  P(@"GLASS_VIEW_PROPS");dumpProps(g,[NSView class],@"GV ");
  P(@"CONTAINER_PROPS");dumpProps(gBox,[NSView class],@"GC ");
  fflush(stdout);
  uint32_t ic=_dyld_image_count();
  for(uint32_t i=0;i<ic;i++){
    const char*nm=_dyld_get_image_name(i);if(!nm)continue;
    const char*base=strrchr(nm,'/');base=base?base+1:nm;
    if(strcmp(base,"AppKit")&&strcmp(base,"SwiftUI")&&strcmp(base,"SwiftUICore")&&strcmp(base,"QuartzCore")&&strcmp(base,"CoreUI"))continue;
    const struct mach_header_64*h=(const struct mach_header_64*)_dyld_get_image_header(i);
    NSString*label=[NSString stringWithUTF8String:base];
    sectionStrings(h,"__TEXT","__swift5_reflstr",label,NO);
    sectionStrings(h,"__TEXT","__cstring",label,YES);
    sectionStrings(h,"__TEXT","__objc_methname",label,YES);
    fflush(stdout);
  }
  P(@"END_INTRO");
}

static NSDictionary*parseSpec(NSString*spec){
  NSMutableDictionary*d=[NSMutableDictionary dictionary];BOOL first=YES;
  for(NSString*p in [spec componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]){
    if(!p.length)continue;if(first){d[@"mode"]=p;first=NO;continue;}
    NSRange r=[p rangeOfString:@"="];if(r.location==NSNotFound)continue;
    d[[p substringToIndex:r.location]]=[p substringFromIndex:r.location+1];
  }
  return d;
}
static double num(NSDictionary*d,NSString*k,double def){NSString*v=d[k];return v?v.doubleValue:def;}
static BOOL keyMatches(NSString*key,NSString*filters){
  NSString*lk=key.lowercaseString;
  for(NSString*f in [filters.lowercaseString componentsSeparatedByString:@","])if(f.length&&[lk containsString:f])return YES;
  return NO;
}
static void runSweep(NSDictionary*sp){
  double t0=nowS();
  int dark=(int)num(sp,@"dark",0),sw=(int)num(sp,@"w",600),shh=(int)num(sp,@"h",72),style=(int)num(sp,@"style",0);
  double sr=num(sp,@"r",24),deadline=num(sp,@"deadline",60),wait=num(sp,@"wait",0.6);
  BOOL extras=num(sp,@"extras",0)!=0,content=num(sp,@"content",0)!=0;
  long vmin=(long)num(sp,@"vmin",0),vmax=(long)num(sp,@"vmax",40);
  NSString*filters=sp[@"keys"]?sp[@"keys"]:@"variant";
  NSString*fix=sp[@"fix"];
  if(fix){NSRange r=[fix rangeOfString:@":"];if(r.location!=NSNotFound){gFixKey=[fix substringToIndex:r.location];gFixVal=(long)[fix substringFromIndex:r.location+1].integerValue;}}
  id<MTLDevice>dev=MTLCreateSystemDefaultDevice();
  P([NSString stringWithFormat:@"BEGIN_PROCESS spec=%@ OS=%@ METAL=%@",sp,NSProcessInfo.processInfo.operatingSystemVersionString,dev?dev.name:@"<nil>"]);
  setupWindow(dark);
  NSArray*ints=setterKeys(gG,YES);
  if(extras){
    for(int s=0;s<2;s++)runCfg(600,44,22,s,nil,0,NO,nil,s==0?1.2:0.8);
    for(int s=0;s<2;s++)runCfg(300,200,28,s,nil,0,NO,nil,0.8);
    for(int s=0;s<2;s++)runCfg(600,72,24,s,nil,0,NO,nil,0.8);
  }
  for(NSArray*k in ints){
    NSString*key=k[0];if(!keyMatches(key,filters))continue;
    int fails=0;
    for(long v=vmin;v<=vmax&&fails<3;v++){if(nowS()-t0>deadline){P(@"DEADLINE_STOP");return;}if(!runCfg(sw,shh,sr,style,key,v,content,nil,wait))fails++;else fails=0;}
  }
  if(!extras)return;
  for(NSArray*k in ints){
    NSString*key=k[0];NSString*lk=key.lowercaseString;
    if(keyMatches(key,filters)||[lk isEqualToString:@"style"])continue;
    BOOL lens=[lk containsString:@"lens"]||[lk containsString:@"content"];
    for(long v=0;v<=3;v++){if(nowS()-t0>deadline){P(@"DEADLINE_STOP");return;}runCfg(600,72,24,0,key,v,NO,nil,wait);if(lens)runCfg(600,72,24,0,key,v,YES,nil,wait);}
  }
  if(nowS()-t0<deadline){runCfg(600,72,24,0,nil,0,YES,nil,wait);runCfg(600,72,24,0,nil,0,YES,NSColor.systemBlueColor,wait);runCfg(600,72,24,1,nil,0,YES,NSColor.systemBlueColor,wait);}
}

static void sh(NSString*cmd,NSString*file){
  const char*args[]={"/bin/sh","-c",cmd.UTF8String,NULL};
  posix_spawn_file_actions_t fa;posix_spawn_file_actions_init(&fa);
  posix_spawn_file_actions_addopen(&fa,1,file.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND,0644);
  posix_spawn_file_actions_adddup2(&fa,1,2);
  pid_t pid;int r=posix_spawn(&pid,"/bin/sh",&fa,NULL,(char*const*)args,environ);
  posix_spawn_file_actions_destroy(&fa);
  if(r==0){int st=0;waitpid(pid,&st,0);}else printf("SH_SPAWN_ERROR %d\n",r);
}

int main(int argc,const char**argv){@autoreleasepool{
  loadCG();
  if(argc==2){
    double t0=nowS();NSString*out=[NSString stringWithUTF8String:argv[1]];
    NSString*q=[NSString stringWithFormat:@"'%@'",out];
    sh([NSString stringWithFormat:@"echo '== sw_vers'; sw_vers; uname -a; echo '== GPU'; system_profiler SPDisplaysDataType 2>&1 | head -60; echo '== dock defaults'; defaults read com.apple.dock 2>&1 | head -120; echo '== screencapture'; screencapture -x %@/screen-before.png 2>&1; ls -la %@",q,q],[out stringByAppendingPathComponent:@"system.txt"]);
    sh(@"D=/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock; echo '== otool'; otool -L \"$D\" 2>&1 | head -150; echo '== strings'; (strings -a \"$D\" 2>/dev/null || LC_ALL=C grep -a -o -E '[[:print:]]{5,}' \"$D\") | grep -i -E 'glass|backdrop|sdf|variant|refract|lens|material|blur|portal|tile|magnif' | sort -u | head -800; echo '== resources'; ls -la /System/Library/CoreServices/Dock.app/Contents/Resources 2>&1 | head -150",[out stringByAppendingPathComponent:@"dock-strings.txt"]);
    sh([NSString stringWithFormat:@"ls -la '/System/Library/Desktop Pictures/' 2>&1; echo '== find'; find '/System/Library/Desktop Pictures' -maxdepth 3 2>/dev/null | head -300; mkdir -p %@/wallpapers; find '/System/Library/Desktop Pictures' -maxdepth 3 -iname '*tahoe*' -type f -size -40M | head -6 | while IFS= read -r f; do cp \"$f\" %@/wallpapers/; done; ls -la %@/wallpapers",q,q,q],[out stringByAppendingPathComponent:@"desktop-pictures.txt"]);
    sh([NSString stringWithFormat:@"if [ -f ./probe_extra.sh ]; then sh ./probe_extra.sh %@; else echo no-extra; fi",q],[out stringByAppendingPathComponent:@"extra.txt"]);
    printf("SHELL_DONE elapsed=%.1f\n",nowS()-t0);fflush(stdout);
    NSArray*modes=@[@"intro",@"sweep dark=0 w=600 h=72 r=24 extras=1 deadline=85",@"sweep dark=1 w=600 h=72 r=24 extras=1 deadline=50",@"sweep dark=0 w=300 h=200 r=28 deadline=35"];
    NSString*mf=[NSString stringWithContentsOfFile:@"probe_modes.txt" encoding:NSUTF8StringEncoding error:nil];
    if(mf){NSMutableArray*mm=[NSMutableArray array];for(NSString*line in [mf componentsSeparatedByString:@"\n"]){NSString*t=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(t.length&&![t hasPrefix:@"#"])[mm addObject:t];}if(mm.count)modes=mm;}
    int childIndex=0;
    for(NSString*m in modes){
      childIndex++;char idx[16];snprintf(idx,sizeof idx,"%d",childIndex);
      if(nowS()-t0>225){printf("PARENT_DEADLINE skip %s\n",m.UTF8String);continue;}
      char*args[]={(char*)argv[0],"--child",idx,(char*)m.UTF8String,(char*)argv[1],NULL};
      pid_t pid;int r=posix_spawn(&pid,argv[0],NULL,NULL,args,environ);
      if(r){printf("SPAWN_ERROR %s %d\n",m.UTF8String,r);continue;}
      int st=0;waitpid(pid,&st,0);
      printf("CHILD_DONE %s exited=%d status=%d signal=%d elapsed=%.1f\n",m.UTF8String,(int)WIFEXITED(st),WIFEXITED(st)?WEXITSTATUS(st):-1,WIFSIGNALED(st)?WTERMSIG(st):0,nowS()-t0);fflush(stdout);
    }
    sh([NSString stringWithFormat:@"screencapture -x %@/screen-after.png 2>&1; ls -la %@ %@/wallpapers; wc -l %@/*.txt",q,q,q,q],[out stringByAppendingPathComponent:@"system.txt"]);
    printf("PARENT_DONE elapsed=%.1f\n",nowS()-t0);
    return 0;
  }
  if(argc!=5||strcmp(argv[1],"--child"))return 4;
  NSString*spec=[NSString stringWithUTF8String:argv[3]];NSString*out=[NSString stringWithUTF8String:argv[4]];
  NSString*file=[out stringByAppendingPathComponent:[NSString stringWithFormat:@"child-%s.txt",argv[2]]];
  if(!freopen(file.fileSystemRepresentation,"w",stdout))return 6;
  setvbuf(stdout,NULL,_IOLBF,0);
  P([@"SPEC " stringByAppendingString:spec]);
  NSDictionary*sp=parseSpec(spec);
  if([sp[@"mode"] isEqualToString:@"intro"])runIntro();
  else if([sp[@"mode"] isEqualToString:@"sweep"])runSweep(sp);
  P(@"END_PROCESS");fflush(stdout);
  return 0;
}}
