// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 8.3: Sửa lỗi Crash Block + Phục hồi NetToolFake
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/types.h>
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

        Class menuVCCls = objc_getClass("_UIOverlayPresentationController");
        if (!menuVCCls) return;

        if ([rootVC.presentedViewController isKindOfClass:menuVCCls]) {
            [rootVC dismissViewControllerAnimated:YES completion:nil];
            return;
        }

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
// 3. Fake NetTool Response (Kết hợp Inject State)
// ------------------------------------------------------------
@interface NetToolFake : NSObject
+ (id)Post_AppendURL:(id)url myparameters:(id)params mysuccess:(id)success myfailure:(id)failure;
+ (BOOL)verifySignature:(id)signature withData:(id)data usingPublicKeyString:(id)key;
@end

@implementation NetToolFake
+ (id)Post_AppendURL:(id)url myparameters:(id)params mysuccess:(id)success myfailure:(id)failure {
    NSString *urlStr = [url description];
    NSLog(@"[LQBypass] 🌐 NetTool POST: %@", urlStr);

    NSDictionary *fakeResponse = nil;
    NSTimeInterval currentUnix = [[NSDate date] timeIntervalSince1970];
    NSNumber *unixNum = @((long long)currentUnix);

    if ([urlStr containsString:@"package-v3"]) {
        NSDictionary *pkgData = @{
            @"packageName": @"com.garena.game.kgvn",
            @"name": @"LienQuanMobile",
            @"ip": @"127.0.0.1"
        };
        fakeResponse = @{
            @"code": @200,
            @"status": @"success",
            @"success": @YES,
            @"unix": unixNum,
            @"data": pkgData
        };
    } else if ([urlStr containsString:@"credential-v3"] || [urlStr containsString:@"key-v3"]) {
        NSDictionary *authData = @{
            @"key": @"VIP-LIFETIME-2099",
            @"status": @"active",
            @"package": @"AOV",
            @"license": @"VIP",
            @"expiredAt": @"2099-12-31 23:59:59",
            @"id": @"88888888"
        };
        fakeResponse = @{
            @"code": @200,
            @"status": @"success",
            @"success": @YES,
            @"unix": unixNum,
            @"data": authData
        };
    } else {
        fakeResponse = @{
            @"code": @200,
            @"status": @"success",
            @"success": @YES,
            @"unix": unixNum,
            @"data": @{}
        };
    }

    if (success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                // TIÊM STATE TRƯỚC KHI GỌI BLOCK CỦA GAME!
                uintptr_t slide = get_awss3_base_slide();
                if (slide) {
                    NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
                    void (*set_token_func)(id) = (void (*)(id))(slide + 0x00CB80A0);
                    set_token_func(seed);
                    NSLog(@"[LQBypass] ✅ Đã Inject Seed State vào hệ thống!");
                }

                // Gọi Block xịn của game
                void (^succBlock)(id, id) = (void (^)(id, id))success;
                succBlock(fakeResponse, nil);
                NSLog(@"[LQBypass] ✅ Đã gọi completion block mạng thành công!");
            } @catch (NSException *e) {
                NSLog(@"[LQBypass] Exception calling success block: %@", e);
            }
        });
    }
    return nil;
}

+ (BOOL)verifySignature:(id)signature withData:(id)data usingPublicKeyString:(id)key {
    return YES;
}
@end

// ------------------------------------------------------------
// Anti-Debug hooks (Fishhook)
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
// Swizzles
// ------------------------------------------------------------
void swizzleMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, newImp);
}

static void dummy_imp(id self, SEL _cmd, ...) {}
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

        // Mute login UI
        Class statusCls = objc_getClass("ASStatusView");
        if (statusCls) {
            swizzleMethod(statusCls, @selector(layoutLoginForm:centerX:centerY:isLandscape:), (IMP)dummy_imp);
            swizzleMethod(statusCls, @selector(layoutExpiredForm:centerX:centerY:isLandscape:), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"validateKey:"), (IMP)fake_validateKey);
        }

        // Mock UDID
        Class cls = objc_getClass("VKKeychainUDID") ?: objc_getClass("VKKeychainIDFV");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"VKgetUdidFromKeyChain"), (IMP)fake_udid_imp);
            swizzleMethod(cls, NSSelectorFromString(@"VKsaveUdidToKeyChain:"), (IMP)dummy_save_udid);
        }
        
        // Fake NetTool
        Class netToolCls = objc_getClass("NetTool");
        if (netToolCls) {
            Method m1 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"));
            if (m1) swizzleMethod(netToolCls, NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"), method_getImplementation(m1));
            Method m2 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"));
            if (m2) swizzleMethod(netToolCls, NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"), method_getImplementation(m2));
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
    NSLog(@"[LQBypass] ⚡ Dylib v8.3 đã nạp!");
    perform_swizzles();

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
