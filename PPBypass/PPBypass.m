// PPBypass.m — Internal bypass + instrumentation cho 8 Ball Pool (libfluorite PPAPIKey)
// Non-JB: ObjC runtime swizzling thuan. Inject bang Sideloadly. KHONG sua byte goc.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>

static NSString *gLog;
static void PPLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    NSLog(@"[PPBYPASS] %@", m);
    if (!gLog) {
        NSString *d = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        gLog = [d stringByAppendingPathComponent:@"pp_bypass.log"];
    }
    NSString *l = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], m];
    FILE *f = fopen(gLog.UTF8String, "a"); if (f){ fputs(l.UTF8String,f); fclose(f);} 
}

static IMP oExit,oLoading,oExpire,oAmount,oDevKey,oCopyKey;

// +[PPEnterKeyView showInView:...] -> chan (khong hien form key)
static id h_showInView(id self, SEL _cmd) { PPLog(@"BLOCK showInView (form key suppressed)"); return nil; }
// -[PPAPIKey exitKey] -> chan (khong tu thoat)
static void h_exit(id self, SEL _cmd) { PPLog(@"BLOCK exitKey (self-exit suppressed)"); }
// quan sat luong (call-through + log)
static void h_loading(id self, SEL _cmd, id x){ PPLog(@"loading: arg=%@", x); ((void(*)(id,SEL,id))oLoading)(self,_cmd,x); }
static id h_expire(id self, SEL _cmd){ id r=((id(*)(id,SEL))oExpire)(self,_cmd); PPLog(@"getKeyExpire -> %p (%@)", r, [r class]); return r; }
static id h_amount(id self, SEL _cmd){ id r=((id(*)(id,SEL))oAmount)(self,_cmd); PPLog(@"getKeyAmount -> %p (%@)", r, [r class]); return r; }
static id h_devkey(id self, SEL _cmd){ id r=((id(*)(id,SEL))oDevKey)(self,_cmd); PPLog(@"getDeviceKey -> %p", r); return r; }
static id h_copyk (id self, SEL _cmd){ id r=((id(*)(id,SEL))oCopyKey)(self,_cmd); PPLog(@"copyKey -> %p", r); return r; }

static void hookI(Class c,SEL s,IMP n,IMP*o){ Method m=class_getInstanceMethod(c,s);
    if(!m){PPLog(@"MISS -[%@ %@]",NSStringFromClass(c),NSStringFromSelector(s));return;}
    *o=method_getImplementation(m); method_setImplementation(m,n); PPLog(@"hook -[%@ %@]",NSStringFromClass(c),NSStringFromSelector(s)); }
static void hookC(Class c,SEL s,IMP n,IMP*o){ Method m=class_getClassMethod(c,s);
    if(!m){PPLog(@"MISS +[%@ %@]",NSStringFromClass(c),NSStringFromSelector(s));return;}
    *o=method_getImplementation(m); method_setImplementation(m,n); PPLog(@"hook +[%@ %@]",NSStringFromClass(c),NSStringFromSelector(s)); }

static void install(void){
    Class E=objc_getClass("PPEnterKeyView"), A=objc_getClass("PPAPIKey");
    PPLog(@"install: PPEnterKeyView=%p PPAPIKey=%p", E, A);
    if(E){ IMP tmp; hookC(E, NSSelectorFromString(@"showInView:title:message:okText:contactText:contactUrl:placeholder:timeout:onSubmit:"), (IMP)h_showInView, &tmp); }
    if(A){
        hookI(A,@selector(exitKey),(IMP)h_exit,&oExit);
        hookI(A,@selector(loading:),(IMP)h_loading,&oLoading);
        hookI(A,@selector(getKeyExpire),(IMP)h_expire,&oExpire);
        hookI(A,@selector(getKeyAmount),(IMP)h_amount,&oAmount);
        hookI(A,@selector(getDeviceKey),(IMP)h_devkey,&oDevKey);
        hookI(A,@selector(copyKey),(IMP)h_copyk,&oCopyKey);
    }
}
static void tryInstall(int n){ if(objc_getClass("PPAPIKey")||n>60){ install(); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ tryInstall(n+1); }); }

__attribute__((constructor)) static void PPBypassInit(void){ PPLog(@"=== PPBypass loaded pid=%d ===",getpid()); tryInstall(0); }
