// =========================================================================
//  LQBypass.m — Tweak Dylib Toàn Diện Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 7.0: Mở Khóa Trực Tiếp Bảng Điều Khiển _UIOverlayPresentationController
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

static id g_modControllerInstance = nil;

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
// 2. Class Helper: Quản lý Bật/Tắt Menu Mod & Dọn Dẹp
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)openModMenu;
+ (void)dismissAllHUDsAndWindows;
+ (void)cleanSubviewsOfView:(UIView *)view;
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

+ (void)cleanSubviewsOfView:(UIView *)view {
    for (UIView *v in [view.subviews copy]) {
        NSString *cls = NSStringFromClass([v class]);
        
        // TUYỆT ĐỐI GIỮ LẠI: Menu Mod (_UIOverlayPresentationController), ImGui, Nút Nổi
        if ([cls containsString:@"_UIOverlayPresentationController"] ||
            [cls containsString:@"ImGui"] || 
            [cls containsString:@"MTKView"] || 
            [cls containsString:@"Toggle"] || 
            [cls containsString:@"Button"]) {
            continue;
        }
        
        // Chỉ xóa đúng các view chặn màn hình
        if ([cls containsString:@"APIClientOverlay"] ||
            [cls containsString:@"ASStatusUDIDAlertView"] ||
            [cls containsString:@"ASHideView"] ||
            [cls containsString:@"JGProgressHUD"] ||
            [cls containsString:@"MBProgressHUD"] ||
            [cls containsString:@"ASProgressHUD"]) {
            v.hidden = YES;
            [v removeFromSuperview];
        } else {
            [self cleanSubviewsOfView:v];
        }
    }
}

+ (void)dismissAllHUDsAndWindows {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            NSString *cls = NSStringFromClass([w class]);
            if ([cls containsString:@"APIClientOverlayWindow"]) {
                w.hidden = YES;
                w.alpha = 0.0;
                [w setRootViewController:nil];
                [w.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
            }
            [self cleanSubviewsOfView:w];
        }
    });
}

@end

// -------------------------------------------------------------------------
// 3. Fake NetTool Response (VIP Schema)
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

    if ([urlStr containsString:@"package-v3"]) {
        NSDictionary *pkgData = @{
            @"packageName": @"com.garena.game.kgvn",
            @"name": @"LienQuanMobile",
            @"ip": @"127.0.0.1",
            @"IP": @"127.0.0.1",
            @"unix": @4102444799,
            @"status": @"success"
        };
        fakeResponse = @{
            @"code": @200,
            @"status": @"success",
            @"success": @YES,
            @"data": pkgData
        };
    } else if ([urlStr containsString:@"credential-v3"] || [urlStr containsString:@"key-v3"]) {
        NSDictionary *authData = @{
            @"key": @"VIP-LIFETIME-2099",
            @"status": @"active",
            @"package": @"AOV",
            @"license": @"VIP",
            @"expiredAt": @"2099-12-31 23:59:59",
            @"unix": @4102444799,
            @"id": @"88888888"
        };
        fakeResponse = @{
            @"code": @200,
            @"status": @"success",
            @"success": @YES,
            @"data": authData
        };
    } else {
        fakeResponse = @{
            @"code": @200,
            @"status": @"success",
            @"success": @YES,
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

static id dummy_init_hidden(id self, SEL _cmd, CGRect frame) {
    struct objc_super sup = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    UIView *v = ((id (*)(struct objc_super *, SEL, CGRect))objc_msgSendSuper)(&sup, _cmd, frame);
    if ([v isKindOfClass:[UIView class]]) {
        v.hidden = YES;
        v.alpha = 0.0;
    }
    return v;
}

static id fake_udid_imp(id self, SEL _cmd) {
    return @"00000000-0000-0000-0000-000000000000";
}

static void dummy_save_udid(id self, SEL _cmd, id udid) {}
static void dummy_showHUD(id self, SEL _cmd, ...) {}

// Hook trực tiếp khi chạm vào Nút Nổi -> Bật ngay Bảng Menu Mod!
static void hook_show_menu_imp(id self, SEL _cmd, id gesture) {
    NSLog(@"[LQBypass] 🔘 Đã chạm vào Nút Nổi -> Kích hoạt mở Bảng Menu Mod!");
    [LQBypassHelper openModMenu];
}

void perform_swizzles(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // --- 5a. Ẩn APIClientOverlayWindow ---
        Class cls = objc_getClass("APIClientOverlayWindow");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"makeKeyAndVisible"), (IMP)dummy_imp);
            swizzleMethod(cls, NSSelectorFromString(@"initWithFrame:"), (IMP)dummy_init_hidden);
        }

        // --- 5b. Mute ASStatusView ---
        cls = objc_getClass("ASStatusView");
        if (cls) {
            NSArray *selList = @[
                @"showLoginForm", @"showExpiredForm", @"showLoginError:",
                @"showLoginLoading", @"showUDIDAlertWithTitle:message:leftTitle:rightTitle:leftAction:rightAction:",
                @"showLoadingWithTitle:message:", @"showSuccessWithTitle:message:", @"showErrorWithTitle:message:",
                @"showErrorWithTitle:message:buttonTitle:", @"showSuccessWithTitle:message:buttonTitle:",
                @"layoutLoginForm:centerX:centerY:isLandscape:", @"layoutExpiredForm:centerX:centerY:isLandscape:"
            ];
            for (NSString *selName in selList) {
                SEL sel = NSSelectorFromString(selName);
                if (sel) swizzleMethod(cls, sel, (IMP)dummy_imp);
            }
        }

        // --- 5c. Ẩn ASHideView & ASStatusUDIDAlertView ---
        cls = objc_getClass("ASHideView");
        if (cls) swizzleMethod(cls, NSSelectorFromString(@"initWithFrame:"), (IMP)dummy_init_hidden);

        cls = objc_getClass("ASStatusUDIDAlertView");
        if (cls) swizzleMethod(cls, NSSelectorFromString(@"configureWithTitle:message:leftTitle:rightTitle:"), (IMP)dummy_imp);

        // --- 5d. Mute HUDs ---
        cls = objc_getClass("JGProgressHUD");
        if (cls) {
            for (NSString *sel in @[@"showInView:", @"showInView:animated:", @"showInView:animated:afterDelay:"]) {
                swizzleMethod(cls, NSSelectorFromString(sel), (IMP)dummy_showHUD);
            }
        }

        cls = objc_getClass("MBProgressHUD");
        if (cls) {
            for (NSString *sel in @[@"showAnimated:", @"showUsingAnimation:"]) {
                swizzleMethod(cls, NSSelectorFromString(sel), (IMP)dummy_showHUD);
            }
        }

        cls = objc_getClass("ASProgressHUD");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"show:"), (IMP)dummy_showHUD);
            swizzleMethod(cls, NSSelectorFromString(@"showUsingAnimation:"), (IMP)dummy_showHUD);
        }

        // --- 5e. Mute ASIndicator ---
        cls = objc_getClass("ASIndicator");
        if (cls) {
            for (NSString *sel in @[
                @"showNotificationWithTitle:message:",
                @"showNotificationWithTitle:message:tapHandler:",
                @"showNotificationWithTitle:message:tapHandler:completion:",
                @"showNotificationWithImage:title:message:"
            ]) {
                swizzleMethod(cls, NSSelectorFromString(sel), (IMP)dummy_imp);
            }
        }

        // --- 5f. Hook Keychain UDID ---
        cls = objc_getClass("VKKeychainUDID");
        if (!cls) cls = objc_getClass("VKKeychainIDFV");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"VKgetUdidFromKeyChain"), (IMP)fake_udid_imp);
            swizzleMethod(cls, NSSelectorFromString(@"VKsaveUdidToKeyChain:"), (IMP)dummy_save_udid);
        }

        // --- 5g. Hook NetTool Fake ---
        Class netToolCls = objc_getClass("NetTool");
        if (netToolCls) {
            Method m1 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"));
            if (m1) swizzleMethod(netToolCls, NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"), method_getImplementation(m1));
            Method m2 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"));
            if (m2) swizzleMethod(netToolCls, NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"), method_getImplementation(m2));
        }

        // --- 5h. Hook showMenu: trên controller nút nổi ---
        Class modCtrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (modCtrlCls) {
            swizzleMethod(modCtrlCls, NSSelectorFromString(@"showMenu:"), (IMP)hook_show_menu_imp);
            NSLog(@"[LQBypass] ✅ Đã gắn hook showMenu: -> openModMenu");
        }

        NSLog(@"[LQBypass] ✅ Swizzles hoàn tất!");
    });
}

// -------------------------------------------------------------------------
// 6. Bootstrap Mod Menu
// -------------------------------------------------------------------------
void bootstrap_mod_menu(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LQBypass] 🚀 Bắt đầu khởi tạo Menu Mod...");

        // Khởi tạo Controller nút nổi
        Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!cls) {
            NSLog(@"[LQBypass] ❌ Không tìm thấy class tXGBBDJNKKzPYcSGmlav");
            return;
        }

        g_modControllerInstance = [[cls alloc] init];
        NSLog(@"[LQBypass] ✅ Đã tạo instance: %@", g_modControllerInstance);

        // Ghi vào BSS cache của AWSS3 @ 0x36BDFD0
        uintptr_t slide = get_awss3_base_slide();
        if (slide) {
            uintptr_t *cache_ptr = (uintptr_t *)(slide + 0x36BDFD0);
            *cache_ptr = (uintptr_t)g_modControllerInstance;
            NSLog(@"[LQBypass] ✅ Đã ghi instance vào BSS cache @ %p", cache_ptr);
        }

        // Gọi lệnh vẽ nút tròn nổi lên màn hình
        if ([g_modControllerInstance respondsToSelector:@selector(initTapGes)]) {
            [g_modControllerInstance performSelector:@selector(initTapGes)];
            NSLog(@"[LQBypass] ✅ Đã gọi [initTapGes]");
        } else if ([g_modControllerInstance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
            [g_modControllerInstance performSelector:@selector(setupFloatingToggleButtons)];
            NSLog(@"[LQBypass] ✅ Đã gọi [setupFloatingToggleButtons]");
        }

        [LQBypassHelper dismissAllHUDsAndWindows];
    });
}

// -------------------------------------------------------------------------
// 7. Constructor
// -------------------------------------------------------------------------
__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] ⚡ Dylib v7.0 đã nạp thành công!");

    perform_swizzles();

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            bootstrap_mod_menu();
        });
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        bootstrap_mod_menu();
    });

    // Cử chỉ chạm 2 ngón 2 lần để mở Bảng Menu Mod
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
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
