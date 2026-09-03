// 8PoolHack.m
// Standalone hack dylib for 8 Ball Pool iOS (mod baked binaries: libfluorite + libloader)
// Strategy:
//   [1] fishhook _abort          → no-op  (blocks ~20s C-level crash from key timeout)
//   [2] fishhook _sysctl         → strip P_TRACED flag (bypass anti-debug sysctl check)
//   [3] fishhook _sysctlbyname   → same, belt-and-suspenders
//   [4] ObjC swizzle PPEnterKeyView.showInView:... → suppress key dialog UI
//   [5] ObjC swizzle PPAPIKey.exitKey → suppress forced self-exit
//   [6] After 6s: locate libloader slide → call sub_52901C (menu builder) directly
//
// All offsets are compile-time (file) offsets from static analysis of the original binaries.
// Runtime addrs = file_offset + ASLR_slide (computed via _dyld_get_image_vmaddr_slide).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
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
// [6] Locate libloader ASLR slide and call menu builder sub_52901C directly
//
//  libloader offsets (from static analysis):
//    sub_52901C  — creates FloatingMenuButton, UIKitMenuView, ImGuiDrawView
//    sub_525434  — gate (CRC32 + anti-debug + game hook init)
//
//  We skip the gate entirely and call the menu builder function pointer directly.
// ─────────────────────────────────────────────────────────────────────────────
#define LIBLOADER_MENU_BUILDER_OFFSET  0x52901CUL  // sub_52901C

static intptr_t get_image_slide(const char *partial) {
    uint32_t cnt = _dyld_image_count();
    for (uint32_t i = 0; i < cnt; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, partial)) {
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            HLog(@"[IMG] '%s' -> slide=0x%lx", partial, (unsigned long)slide);
            return slide;
        }
    }
    HLog(@"[WARN] image '%s' not found in dyld list", partial);
    return 0;
}

static void trigger_menu(void) {
    intptr_t slide = get_image_slide("libloader");
    if (!slide) {
        HLog(@"[ERR] libloader not found — menu will not appear");
        return;
    }
    uintptr_t menu_fn_addr = (uintptr_t)slide + LIBLOADER_MENU_BUILDER_OFFSET;
    HLog(@"[MENU] Calling sub_52901C @ 0x%lx (slide=0x%lx + 0x%lx)",
         (unsigned long)menu_fn_addr, (unsigned long)slide, LIBLOADER_MENU_BUILDER_OFFSET);

    void (*build_menu)(void) = (void (*)(void))menu_fn_addr;
    build_menu();
    HLog(@"[MENU] sub_52901C returned — menu builder completed");
}

// ─────────────────────────────────────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────────────────────────────────────
__attribute__((constructor)) static void hack_init(void) {
    HLog(@"=== 8PoolHack loaded pid=%d ===", getpid());

    // [1][2][3] C-level hooks via fishhook (GOT rebinding)
    struct rebinding hooks[] = {
        {"abort",         fake_abort,         (void **)&orig_abort},
        {"sysctl",        fake_sysctl,         (void **)&orig_sysctl},
        {"sysctlbyname",  fake_sysctlbyname,   (void **)&orig_sysctlbyname},
    };
    rebind_symbols(hooks, sizeof(hooks) / sizeof(hooks[0]));
    HLog(@"[INIT] fishhook: abort + sysctl + sysctlbyname hooked");

    // [4][5] ObjC swizzles — poll until PPAPIKey/PPEnterKeyView classes are available
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

    // [6] Menu trigger after 6 seconds — game + libloader should be fully loaded by then
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            HLog(@"[MENU] 6s delay done — triggering menu bootstrap...");
            trigger_menu();
        }
    );
}
