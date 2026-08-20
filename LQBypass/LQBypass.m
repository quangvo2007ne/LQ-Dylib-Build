// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 8.4: Mute 100% ASStatusView & Force Inner Success Block
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import "fishhook.h"

uintptr_t get_awss3_base_slide(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "AWSS3.framework/AWSS3")) {
            return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// ------------------------------------------------------------
// Helper: Mở Menu Mod
// ------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)openModMenu;
@end

@implementation LQBypassHelper

+ (void)openModMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin && [UIApplication sharedApplication].windows.count > 0)
            keyWin = [UIApplication sharedApplication].windows.firstObject;
        UIViewController *rootVC = keyWin.rootViewController;
        if (!rootVC) return;

        // Toggle ImGui
        Class imguiCls = objc_getClass("ImGuiDrawView");
        if (imguiCls) {
            SEL setVis = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
            SEL getVis = NSSelectorFromString(@"GmmtbwBOlBYaQRpBHDVm");
            if ([imguiCls respondsToSelector:getVis] && [imguiCls respondsToSelector:setVis]) {
                BOOL cur = ((BOOL (*)(id, SEL))objc_msgSend)(imguiCls, getVis);
                ((void (*)(id, SEL, BOOL))objc_msgSend)(imguiCls, setVis, !cur);
            }
        }

        // Mở _UIOverlayPresentationController
        Class menuVCCls = objc_getClass("_UIOverlayPresentationController");
        if (!menuVCCls) return;

        if ([rootVC.presentedViewController isKindOfClass:menuVCCls]) {
            [rootVC dismissViewControllerAnimated:YES completion:nil];
            return;
        }

        // Reset guard 0x36C0D00
        uintptr_t slide = get_awss3_base_slide();
        if (slide) {
            uint8_t *guard = (uint8_t *)(slide + 0x36C0D00);
            *guard = 0;
        }

        UIViewController *menuVC = [[menuVCCls alloc] init];
        menuVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
        menuVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [rootVC presentViewController:menuVC animated:YES completion:^{
            NSLog(@"[LQBypass] 🚀 Menu đã bung!");
        }];
    });
}
@end

// ------------------------------------------------------------
// Anti-Debug hooks
// ------------------------------------------------------------
static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int (*orig_sysctl)(int*, u_int, void*, size_t*, void*, size_t);
static int (*orig_connect)(int, const struct sockaddr*, socklen_t);

int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 31) return 0;
    return orig_ptrace ? orig_ptrace(request, pid, addr, data) : -1;
}

int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
    if (ret == 0 && namelen == 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID) {
        if (oldp) {
            struct kinfo_proc *info = (struct kinfo_proc *)oldp;
            if (info->kp_proc.p_flag & P_TRACED) {
                info->kp_proc.p_flag &= ~P_TRACED;
            }
        }
    }
    return ret;
}

int my_connect(int socket, const struct sockaddr *address, socklen_t address_len) {
    if (address->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)address;
        if (ntohs(sin->sin_port) == 27042) return -1;
    }
    return orig_connect ? orig_connect(socket, address, address_len) : -1;
}

// ------------------------------------------------------------
// Gọi trực tiếp inner completion block 0x02F085B4
// ------------------------------------------------------------
void force_bootstrap_menu(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uintptr_t slide = get_awss3_base_slide();
        if (!slide) return;

        // Set token (seed) vào State của API Client
        NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
        void (*set_token)(id) = (void (*)(id))(slide + 0x00CB80A0);
        if (set_token) set_token(seed);

        // Inner block tạo menu
        void (*menu_block)(id, id) = (void (*)(id, id))(slide + 0x02F085B4);
        NSDictionary *fakeResp = @{
            @"status": @"success",
            @"unix": @((long long)[[NSDate date] timeIntervalSince1970]),
            @"code": @200,
            @"success": @YES,
            @"data": @{
                @"key": @"VIP-LIFETIME-2099",
                @"status": @"active",
                @"package": @"AOV",
                @"license": @"VIP",
                @"expiredAt": @"2099-12-31 23:59:59",
                @"id": @"88888888"
            }
        };

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (menu_block) {
                menu_block(fakeResp, nil);
                NSLog(@"[LQBypass] ✅ Đã ép gọi inner success block (0x02F085B4)!");
            }
        });
    });
}

// ------------------------------------------------------------
// Swizzles (Mute 100% UI Lỗi/Key)
// ------------------------------------------------------------
void swizzleMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, newImp);
}

static void dummy_imp(id self, SEL _cmd, ...) {
    NSLog(@"[LQBypass] 🔇 Đã chặn hàm hiển thị UI của ASStatusView: %@", NSStringFromSelector(_cmd));
}
static id fake_udid_imp(id self, SEL _cmd) { return @"00000000-0000-0000-0000-000000000000"; }
static void dummy_save_udid(id self, SEL _cmd, id udid) {}
static BOOL fake_validateKey(id self, SEL _cmd, NSString *key) { return YES; }

void perform_swizzles(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Anti-debug
        struct rebinding rebindings[] = {
            {"ptrace", my_ptrace, (void **)&orig_ptrace},
            {"sysctl", my_sysctl, (void **)&orig_sysctl},
            {"connect", my_connect, (void **)&orig_connect},
        };
        rebind_symbols(rebindings, 3);

        // Mute 100% các hàm hiển thị bảng Key/Lỗi của ASStatusView
        Class statusCls = objc_getClass("ASStatusView");
        if (statusCls) {
            swizzleMethod(statusCls, @selector(layoutLoginForm:centerX:centerY:isLandscape:), (IMP)dummy_imp);
            swizzleMethod(statusCls, @selector(layoutExpiredForm:centerX:centerY:isLandscape:), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"showErrorWithTitle:message:buttonTitle:"), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"showErrorWithTitle:message:"), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"showExpiredWithTitle:message:changeKeyTitle:copyUDIDTitle:copyKeyTitle:countdownFrom:"), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"showUDIDAlertWithTitle:message:leftTitle:rightTitle:leftAction:rightAction:"), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"validateKey:"), (IMP)fake_validateKey);
        }

        // Mock UDID
        Class cls = objc_getClass("VKKeychainUDID") ?: objc_getClass("VKKeychainIDFV");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"VKgetUdidFromKeyChain"), (IMP)fake_udid_imp);
            swizzleMethod(cls, NSSelectorFromString(@"VKsaveUdidToKeyChain:"), (IMP)dummy_save_udid);
        }

        // Hook showMenu:
        Class modCtrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (modCtrlCls) {
            SEL showMenuSel = NSSelectorFromString(@"showMenu:");
            IMP hookImp = imp_implementationWithBlock(^(id self, id gesture) {
                NSLog(@"[LQBypass] 🔘 showMenu: gọi openModMenu");
                [LQBypassHelper openModMenu];
            });
            swizzleMethod(modCtrlCls, showMenuSel, hookImp);
        }
    });
}

// ------------------------------------------------------------
// Constructor
// ------------------------------------------------------------
__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] ⚡ Dylib v8.4 đã nạp!");

    perform_swizzles();

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            force_bootstrap_menu();
        });
    }];

    // Backup gesture
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin) keyWin = [UIApplication sharedApplication].windows.firstObject;
        if (keyWin) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                           initWithTarget:[LQBypassHelper class]
                                           action:@selector(openModMenu)];
            tap.numberOfTouchesRequired = 2;
            tap.numberOfTapsRequired = 2;
            [keyWin addGestureRecognizer:tap];
        }
    });
}
