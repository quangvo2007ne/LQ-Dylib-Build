// 8PoolHack.m
// Standalone bypass dylib for 8 Ball Pool iOS mod (libfluorite + libloader)
//
// Architecture (confirmed by static analysis):
//   libfluorite.dylib (66 MB)   — mod engine: menu UI + game hooks + key gate (PPAPIKey, PPEnterKeyView)
//   libloader.framework/libloader — Tencent AnoSDK anti-cheat (NOT the mod menu)
//
// Strategy:
//   [1] fishhook _abort              → no-op (blocks C-level crash from key timeout)
//   [2] fishhook _sysctl             → strip P_TRACED (bypass anti-debug sysctl check)
//   [3] fishhook _sysctlbyname       → same, covers sub_625A24 in libfluorite
//   [4] ObjC swizzle PPEnterKeyView  → suppress key entry dialog
//   [5] ObjC swizzle PPAPIKey.exitKey → suppress forced self-exit
//   [6] ObjC swizzle PPAPIKey.loading: → log key payload
//   [7] fishhook _AnoSDKGetReportData → return 0 (no anomaly data sent)
//   [8] fishhook _AnoSDKInit          → no-op (prevents AnoSDK from initializing detection)
//   [9] swizzle UIViewController presentViewController → block security alert dialogs
//
// After these hooks are in place, libfluorite's own __mod_init_func constructors
// (InitFunc_0 through InitFunc_4) run normally and present the mod menu overlay.
// No separate menu builder call is needed — the menu lives in libfluorite, not libloader.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "CustomModMenu.h"
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <mach-o/dyld.h>
#include "fishhook.h"

// ─────────────────────────────────────────────────────────────────────────────
// Logging
// ─────────────────────────────────────────────────────────────────────────────
static NSString *g_logPath;
static void HLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    NSLog(@"[8HACK] %@", msg);
    if (!g_logPath) {
        NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        g_logPath = [doc stringByAppendingPathComponent:@"8hack.log"];
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    FILE *f = fopen(g_logPath.UTF8String, "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
}

// ─────────────────────────────────────────────────────────────────────────────
// [1] fishhook: abort() → no-op
//     Prevents ~20-second C-level crash: libfluorite dispatch engine calls
//     abort() (GOT 0x3F01FA0) when key validation fails. ObjC swizzle cannot
//     catch this — only a C-level GOT hook works.
// ─────────────────────────────────────────────────────────────────────────────
static void (*orig_abort)(void) = NULL;
static void fake_abort(void) {
    HLog(@"[HOOK] abort() suppressed");
    // intentionally do nothing — game keeps running
}

// ─────────────────────────────────────────────────────────────────────────────
// [2] fishhook: sysctl → strip P_TRACED from kinfo_proc
//     sub_43D830 in libfluorite calls sysctl(KERN_PROC, KERN_PROC_PID, ...)
//     and checks kinfo_proc.kp_proc.p_flag & P_TRACED (0x800).
// ─────────────────────────────────────────────────────────────────────────────
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;
static int fake_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int r = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (r == 0 && namelen >= 4 && name[0] == CTL_KERN && name[1] == KERN_PROC
        && oldp && oldlenp && *oldlenp >= 36) {
        // kinfo_proc.kp_proc.p_flag is at byte offset 32 inside the struct
        uint32_t *pflags = (uint32_t *)((uint8_t *)oldp + 32);
        if (*pflags & 0x800) {
            *pflags &= ~(uint32_t)0x800;
            HLog(@"[HOOK] sysctl: stripped P_TRACED from kinfo_proc");
        }
    }
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// [3] fishhook: sysctlbyname → same idea, suppress any debugger detection
// ─────────────────────────────────────────────────────────────────────────────
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;
static int fake_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int r = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    // "kern.proc.pid.*" style check — zero any int result to avoid debugger detection
    if (name && strstr(name, "kern.proc") && oldp && oldlenp && *oldlenp == 4) {
        uint32_t *pflags = (uint32_t *)oldp;
        if (*pflags & 0x800) { *pflags &= ~(uint32_t)0x800; }
    }
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// [4][5] ObjC swizzles: PPEnterKeyView + PPAPIKey
// ─────────────────────────────────────────────────────────────────────────────
static BOOL g_swizzled = NO;
static void install_objc_hooks(void) {
    if (g_swizzled) return;

    // [4] Block key entry dialog
    Class enterKeyViewClass = objc_getClass("PPEnterKeyView");
    if (enterKeyViewClass) {
        SEL showSel = NSSelectorFromString(
            @"showInView:title:message:okText:contactText:contactUrl:placeholder:timeout:onSubmit:");
        Method m = class_getClassMethod(enterKeyViewClass, showSel);
        if (m) {
            method_setImplementation(m, imp_implementationWithBlock(
                ^id(id self, ...) {
                    HLog(@"[HOOK] +[PPEnterKeyView showInView:...] BLOCKED (key dialog suppressed)");
                    return nil;
                }
            ));
            HLog(@"[HOOK] PPEnterKeyView.showInView:... -> blocked");
        } else {
            HLog(@"[WARN] PPEnterKeyView.showInView:... method not found");
        }
        g_swizzled = YES;
    }

    // [5] Block forced self-exit from PPAPIKey
    Class apiKeyClass = objc_getClass("PPAPIKey");
    if (apiKeyClass) {
        Method exitM = class_getInstanceMethod(apiKeyClass, @selector(exitKey));
        if (exitM) {
            method_setImplementation(exitM, imp_implementationWithBlock(
                ^void(id self) { HLog(@"[HOOK] -[PPAPIKey exitKey] BLOCKED"); }
            ));
            HLog(@"[HOOK] PPAPIKey.exitKey -> blocked");
        }
        // Also hook -[PPAPIKey loading:] to log the key payload for analysis
        SEL loadingSel = @selector(loading:);
        Method loadingM = class_getInstanceMethod(apiKeyClass, loadingSel);
        if (loadingM) {
            IMP origLoading = method_getImplementation(loadingM);
            method_setImplementation(loadingM, imp_implementationWithBlock(
                ^void(id self, id arg) {
                    HLog(@"[LOG] -[PPAPIKey loading:] arg=%@ class=%@", arg, [arg class]);
                    ((void(*)(id,SEL,id))origLoading)(self, loadingSel, arg);
                }
            ));
            HLog(@"[HOOK] PPAPIKey.loading: -> observed");
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// [9] Swizzle UIViewController.presentViewController to block AnoSDK alert dialogs
//
// AnoSDK shows alerts via standard UIAlertController when it detects:
//   REF 7215 — foreign dylib in image list
//   REF 6960 — code signature mismatch (re-sign by Sideloadly)
// We intercept presentViewController, check message content, and drop it.
// ─────────────────────────────────────────────────────────────────────────────
static IMP orig_presentVC = NULL;
static void fake_presentVC(UIViewController *self, UIViewController *vc,
                           BOOL animated, void (^completion)(void)) {
    if ([vc isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)vc;
        NSString *msg = alert.message ?: @"";
        // Block any AnoSDK / anti-tamper security alerts by known keywords
        if ([msg containsString:@"security threat"] ||
            [msg containsString:@"attack on this"] ||
            [msg containsString:@"app will close"] ||
            [msg containsString:@"Support REF:"] ||
            [msg containsString:@"contact your administrator"]) {
            HLog(@"[BLOCK] AnoSDK alert suppressed: %@", msg);
            if (completion) completion();
            return;
        }
    }
    ((void(*)(id,SEL,id,BOOL,void(^)(void)))orig_presentVC)(
        self, @selector(presentViewController:animated:completion:), vc, animated, completion);
}

static void install_alert_suppressor(void) {
    Class vcClass = [UIViewController class];
    SEL sel = @selector(presentViewController:animated:completion:);
    Method m = class_getInstanceMethod(vcClass, sel);
    if (m) {
        orig_presentVC = method_setImplementation(m, (IMP)fake_presentVC);
        HLog(@"[HOOK] UIViewController.presentViewController: → AnoSDK alert filter installed");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// [6] Diagnostic: log mod-related loaded images
//
// NOTE: libloader = Tencent AnoSDK (NOT the mod menu).
//       The mod menu is initialized by libfluorite.dylib constructors automatically.
//       No manual menu bootstrap call is needed.
//       Exports of libloader confirmed: _AnoSDKInit, _AnoSDKIoctl, _AnoSDKSetUserInfo, etc.
// ─────────────────────────────────────────────────────────────────────────────
static void log_loaded_images(void) {
    uint32_t cnt = _dyld_image_count();
    HLog(@"[IMG] Loaded images: %d", cnt);
    for (uint32_t i = 0; i < cnt; i++) {
        const char *name = _dyld_get_image_name(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (name && (strstr(name, "fluorite") || strstr(name, "loader") || strstr(name, "8PoolHack"))) {
            HLog(@"[IMG] [%d] slide=0x%lx  %s", i, (unsigned long)slide, name);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────────────────────────────────────
__attribute__((constructor)) static void hack_init(void) {
    HLog(@"=== 8PoolHack loaded pid=%d ===", getpid());

    // [1][2][3][7][8] C-level hooks via fishhook (GOT rebinding)
    static int fake_anosdk_init(uint32_t gameId, const char *appKey) {
        HLog(@"[BLOCK] _AnoSDKInit called — suppressed (gameId=%u)", gameId);
        return 0;
    }
    static int fake_anosdk_report(void *buf, uint32_t *len) {
        HLog(@"[BLOCK] _AnoSDKGetReportData called — returning empty");
        if (len) *len = 0;
        return 0;
    }
    struct rebinding hooks[] = {
        {"abort",                fake_abort,           (void **)&orig_abort},
        {"sysctl",               fake_sysctl,          (void **)&orig_sysctl},
        {"sysctlbyname",         fake_sysctlbyname,    (void **)&orig_sysctlbyname},
        {"AnoSDKInit",           fake_anosdk_init,     NULL},
        {"AnoSDKGetReportData",  fake_anosdk_report,   NULL},
        {"AnoSDKGetReportData2", fake_anosdk_report,   NULL},
        {"AnoSDKGetReportData3", fake_anosdk_report,   NULL},
        {"AnoSDKGetReportData4", fake_anosdk_report,   NULL},
    };
    rebind_symbols(hooks, sizeof(hooks) / sizeof(hooks[0]));
    HLog(@"[INIT] fishhook: abort+sysctl+sysctlbyname+AnoSDK hooks installed");

    // [9] Alert suppressor — must run on main thread immediately
    dispatch_async(dispatch_get_main_queue(), ^{ install_alert_suppressor(); });

    // [4][5] ObjC swizzles — poll until PPAPIKey/PPEnterKeyView classes available
    dispatch_async(dispatch_get_main_queue(), ^{
        __block int tries = 0;
        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW,
                                  (uint64_t)(0.5 * NSEC_PER_SEC), 0);
        dispatch_source_set_event_handler(timer, ^{
            tries++;
            if (objc_getClass("PPAPIKey") || tries > 40) {
                install_objc_hooks();
                dispatch_cancel(timer);
            }
        });
        dispatch_resume(timer);
    });

    // [6] Hiển thị UI Mod Menu tự thiết kế (Dark Glassmorphism) sau 3 giây
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            log_loaded_images();
            [[CustomModMenu sharedInstance] showFloatingButton];
            HLog(@"[UI] Custom Mod Menu Floating Button initialized!");
        }
    );
}
