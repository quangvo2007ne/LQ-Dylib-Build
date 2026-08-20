// =========================================================================
//  LQBypass.m — Tweak Dylib Toàn Diện Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 8.1: Anti-Debug, Mock API-Client State & Bootstrap Hoàn Hảo
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <sys/types.h>
#import <sys/sysctl.h>

static id g_imguiViewController = nil;

// -------------------------------------------------------------------------
// 1. Helper: Tìm Image Base Slide của AWSS3.framework
// -------------------------------------------------------------------------
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

// -------------------------------------------------------------------------
// 2. Class Helper: Quản lý Bật/Tắt Menu Mod
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)openModMenu;
@end

@implementation LQBypassHelper

+ (void)openModMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin && [UIApplication sharedApplication].windows.count > 0) {
            keyWin = [UIApplication sharedApplication].windows.firstObject;
        }
        UIViewController *rootVC = keyWin.rootViewController;
        if (!rootVC) {
            NSLog(@"[LQBypass] ⚠️ Không tìm thấy rootViewController");
            return;
        }

        // 1. Toggle hiển thị ImGui (Radar/ESP)
        Class imguiCls = objc_getClass("ImGuiDrawView");
        if (imguiCls) {
            SEL setVisSel = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
            SEL getVisSel = NSSelectorFromString(@"GmmtbwBOlBYaQRpBHDVm");
            if ([imguiCls respondsToSelector:getVisSel] && [imguiCls respondsToSelector:setVisSel]) {
                BOOL (*getVis)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
                void (*setVis)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
                BOOL cur = getVis(imguiCls, getVisSel);
                setVis(imguiCls, setVisSel, !cur);
            }
        }

        // 2. Mở bảng cài đặt Mod Menu chính (_UIOverlayPresentationController)
        Class menuVCCls = objc_getClass("_UIOverlayPresentationController");
        if (!menuVCCls) {
            NSLog(@"[LQBypass] ❌ Không tìm thấy class _UIOverlayPresentationController");
            return;
        }

        // Nếu menu đang hiển thị -> đóng lại
        if ([rootVC.presentedViewController isKindOfClass:menuVCCls]) {
            [rootVC dismissViewControllerAnimated:YES completion:^{
                NSLog(@"[LQBypass] 🔽 Đã đóng Bảng Menu Mod");
            }];
            return;
        }

        // Reset cờ guard chống mở lặp @ 0x36C0D00
        uintptr_t slide = get_awss3_base_slide();
        if (slide) {
            uint8_t *guard_ptr = (uint8_t *)(slide + 0x36C0D00);
            *guard_ptr = 0;
        }

        // Khởi tạo và bung Bảng Menu Mod
        UIViewController *menuVC = [[menuVCCls alloc] init];
        if (menuVC) {
            menuVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
            menuVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
            [rootVC presentViewController:menuVC animated:YES completion:^{
                NSLog(@"[LQBypass] 🚀 BẢNG MENU MOD ĐÃ BUNG LÊN MÀN HÌNH THÀNH CÔNG!");
            }];
        }
    });
}
@end

// -------------------------------------------------------------------------
// 3. Fake NetTool Response (VIP Schema - AWSS3 v2)
// -------------------------------------------------------------------------
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
            @"status": @"success", // Phải khác account_not_activated
            @"success": @YES,
            @"unix": unixNum,      // Root unix cho time check
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
                void (^succBlock)(id, id) = (void (^)(id, id))success;
                succBlock(fakeResponse, nil);
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

// -------------------------------------------------------------------------
// 4. Hook Utility & Swizzles
// -------------------------------------------------------------------------
void swizzleMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, newImp);
}

static void dummy_imp(id self, SEL _cmd, ...) {}

static id fake_udid_imp(id self, SEL _cmd) {
    return @"00000000-0000-0000-0000-000000000000";
}

static void dummy_save_udid(id self, SEL _cmd, id udid) {}

static void hook_show_menu_imp(id self, SEL _cmd, id gesture) {
    NSLog(@"[LQBypass] 🔘 Đã chạm vào Nút Nổi -> Kích hoạt mở Bảng Menu Mod!");
    [LQBypassHelper openModMenu];
}

// -------------------------------------------------------------------------
// 5. Anti-Debug Bypass (ptrace, sysctl, connect)
// -------------------------------------------------------------------------
#import <sys/socket.h>
#import <netinet/in.h>

#import "fishhook.h"

// Original function pointers
static int (*orig_ptrace)(int _request, pid_t _pid, caddr_t _addr, int _data);
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int (*orig_connect)(int socket, const struct sockaddr *address, socklen_t address_len);

// Hook implementations
int my_ptrace(int _request, pid_t _pid, caddr_t _addr, int _data) {
    if (_request == 31) { // PT_DENY_ATTACH
        NSLog(@"[LQBypass] 🛡️ Chặn ptrace(PT_DENY_ATTACH)");
        return 0;
    }
    return orig_ptrace ? orig_ptrace(_request, _pid, _addr, _data) : -1;
}

int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
    if (ret == 0 && namelen == 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID) {
        if (oldp) {
            struct kinfo_proc *info = (struct kinfo_proc *)oldp;
            if (info->kp_proc.p_flag & P_TRACED) {
                NSLog(@"[LQBypass] 🛡️ Chặn sysctl dò P_TRACED");
                info->kp_proc.p_flag &= ~P_TRACED; // Clear the traced flag
            }
        }
    }
    return ret;
}

int my_connect(int socket, const struct sockaddr *address, socklen_t address_len) {
    if (address->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)address;
        if (ntohs(sin->sin_port) == 27042) {
            NSLog(@"[LQBypass] 🛡️ Chặn connect tới port debug 27042");
            return -1; // Connection refused
        }
    }
    return orig_connect ? orig_connect(socket, address, address_len) : -1;
}

// -------------------------------------------------------------------------
// 6. Direct Bootstrap (Bypass Network Flow)
// -------------------------------------------------------------------------
void force_bootstrap_menu(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LQBypass] 🚀 Đang mock API-Client state và Bootstrap Menu trực tiếp...");

        uintptr_t slide = get_awss3_base_slide();
        if (!slide) {
            NSLog(@"[LQBypass] ❌ Lỗi: Không tìm thấy slide của AWSS3");
            return;
        }

        // Mock State API-Client
        NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
        
        // Gọi _apiclient_set_token (0x00CB80A0)
        void (*set_token_func)(id) = (void (*)(id))(slide + 0x00CB80A0);
        @try {
            set_token_func(seed);
            NSLog(@"[LQBypass] ✅ Đã set mock token (seed)");
        } @catch (NSException *e) {
            NSLog(@"[LQBypass] ⚠️ Lỗi set token: %@", e);
        }

        // Gọi Completion Block tạo Menu (0x02F085B4)
        // Completion block nhận 2 tham số: response data và error
        void (*menu_bootstrap_block)(id, id) = (void (*)(id, id))(slide + 0x02F085B4);
        
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

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                menu_bootstrap_block(fakeResp, nil);
                NSLog(@"[LQBypass] ✅ Đã gọi completion block (0x02F085B4) thành công!");
            } @catch (NSException *e) {
                NSLog(@"[LQBypass] ❌ Exception khi gọi block: %@", e);
            }
        });
    });
}

void perform_swizzles(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        
        // 1. Hook Anti-Debug using fishhook
        struct rebinding rebindings[] = {
            {"ptrace", my_ptrace, (void **)&orig_ptrace},
            {"sysctl", my_sysctl, (void **)&orig_sysctl},
            {"connect", my_connect, (void **)&orig_connect},
        };
        rebind_symbols(rebindings, 3);
        NSLog(@"[LQBypass] 🛡️ Anti-debug hooks applied");

        // 2. Mute Login UI
        Class statusCls = objc_getClass("ASStatusView");
        if (statusCls) {
            swizzleMethod(statusCls, NSSelectorFromString(@"layoutLoginForm:centerX:centerY:isLandscape:"), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"layoutExpiredForm:centerX:centerY:isLandscape:"), (IMP)dummy_imp);
        }

        // 3. Mock Keychain
        Class cls = objc_getClass("VKKeychainUDID");
        if (!cls) cls = objc_getClass("VKKeychainIDFV");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"VKgetUdidFromKeyChain"), (IMP)fake_udid_imp);
            swizzleMethod(cls, NSSelectorFromString(@"VKsaveUdidToKeyChain:"), (IMP)dummy_save_udid);
        }

        // 4. Fake NetTool
        Class netToolCls = objc_getClass("NetTool");
        if (netToolCls) {
            Method m1 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"));
            if (m1) swizzleMethod(netToolCls, NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"), method_getImplementation(m1));
            Method m2 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"));
            if (m2) swizzleMethod(netToolCls, NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"), method_getImplementation(m2));
        }

        // 5. Show Menu Hook
        Class modCtrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (modCtrlCls) {
            swizzleMethod(modCtrlCls, NSSelectorFromString(@"showMenu:"), (IMP)hook_show_menu_imp);
            NSLog(@"[LQBypass] ✅ Đã gắn hook showMenu: -> openModMenu");
        }

        NSLog(@"[LQBypass] ✅ Swizzles hoàn tất!");
    });
}

// -------------------------------------------------------------------------
// 7. Constructor
// -------------------------------------------------------------------------
__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] ⚡ Dylib v8.1 đã nạp thành công!");

    perform_swizzles();

    // Thay vì chờ Network Flow, chúng ta chủ động Inject State và gọi thẳng block tạo Menu
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            force_bootstrap_menu();
        });
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin && [UIApplication sharedApplication].windows.count > 0)
            keyWin = [UIApplication sharedApplication].windows.firstObject;
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
