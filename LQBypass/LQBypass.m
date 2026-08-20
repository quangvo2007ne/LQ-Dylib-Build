// =========================================================================
//  LQBypass.m — Tweak Dylib Toàn Diện Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 5.0 (Ultimate VIP Edition) – Mô phỏng chuẩn xác 100% Business Schema
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
// 2. Class Helper: Dọn Dẹp Màn Hình & Điều Khiển Menu Mod
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)toggleImGuiMenu;
+ (void)forceCleanAllOverlays;
+ (void)dismissAllHUDsAndWindows;
+ (void)cleanSubviewsOfView:(UIView *)view;
@end

@implementation LQBypassHelper

+ (void)cleanSubviewsOfView:(UIView *)view {
    for (UIView *v in [view.subviews copy]) {
        NSString *cls = NSStringFromClass([v class]);
        // Giữ lại ImGui và các nút tròn nổi toggle
        if ([cls containsString:@"ImGui"] || [cls containsString:@"Toggle"] || [cls containsString:@"Button"]) {
            continue;
        }
        // Loại bỏ mọi view làm mờ, tối, HUD, loading, alert
        if ([cls containsString:@"HUD"] || [cls containsString:@"Status"] ||
            [cls containsString:@"Alert"] || [cls containsString:@"Loading"] ||
            [cls containsString:@"Progress"] || [cls containsString:@"Indicator"] ||
            [cls containsString:@"HideView"] || [cls containsString:@"VisualEffect"]) {
            v.hidden = YES;
            [v removeFromSuperview];
        } else {
            // Đệ quy quét sạch các cấp view con bên trong
            [self cleanSubviewsOfView:v];
        }
    }
}

+ (void)dismissAllHUDsAndWindows {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            NSString *cls = NSStringFromClass([w class]);
            if ([cls containsString:@"Overlay"] || [cls containsString:@"Status"] ||
                [cls containsString:@"HUD"] || [cls containsString:@"Alert"]) {
                w.hidden = YES;
                w.alpha = 0.0;
                [w setRootViewController:nil];
                [w.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
            }
            [self cleanSubviewsOfView:w];
        }
    });
}

+ (void)forceCleanAllOverlays {
    // Quét liên tục dọn sạch màn hình trong 6 giây đầu
    for (int i = 0; i < 20; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self dismissAllHUDsAndWindows];
        });
    }
}

+ (void)toggleImGuiMenu {
    Class imguiCls = objc_getClass("ImGuiDrawView");
    if (!imguiCls) return;
    SEL getVisSel = NSSelectorFromString(@"GmmtbwBOlBYaQRpBHDVm");
    SEL setVisSel = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
    if (![imguiCls respondsToSelector:getVisSel] || ![imguiCls respondsToSelector:setVisSel]) return;
    BOOL (*getVis)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    void (*setVis)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
    BOOL current = getVis(imguiCls, getVisSel);
    setVis(imguiCls, setVisSel, !current);
    NSLog(@"[LQBypass] 🔄 Toggle ImGui Menu: %d -> %d", current, !current);
}
@end

// -------------------------------------------------------------------------
// 3. Fake NetTool: Cung cấp đầy đủ cấu trúc VIP 2099 chuẩn Business Schema
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

    // 1. Phản hồi cho endpoint Package (sub_E0AE00)
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
        NSLog(@"[LQBypass] 📦 Trả về Fake Package Success: com.garena.game.kgvn");
    }
    // 2. Phản hồi cho endpoint Credential & Key Login (sub_E79D84 & sub_F00168)
    else if ([urlStr containsString:@"credential-v3"] || [urlStr containsString:@"key-v3"]) {
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
        NSLog(@"[LQBypass] 👑 Trả về Fake VIP License đến năm 2099!");
    }
    // 3. Phản hồi cho Snapshot và các API phụ
    else {
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
                // Gọi chuẩn 2 tham số ABI: (id data, id extra)
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
// 4. Các tiện ích Hook & Dummy IMPs
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

// -------------------------------------------------------------------------
// 5. Thực hiện toàn bộ Swizzle
// -------------------------------------------------------------------------
void perform_swizzles(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // --- 5a. Ẩn APIClientOverlayWindow ---
        Class cls = objc_getClass("APIClientOverlayWindow");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"makeKeyAndVisible"), (IMP)dummy_imp);
            swizzleMethod(cls, NSSelectorFromString(@"initWithFrame:"), (IMP)dummy_init_hidden);
            NSLog(@"[LQBypass] ✅ APIClientOverlayWindow muted");
        }

        // --- 5b. Mute toàn bộ Dialog của ASStatusView ---
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
            NSLog(@"[LQBypass] ✅ ASStatusView muted");
        }

        // --- 5c. Ẩn ASHideView & ASStatusUDIDAlertView ---
        cls = objc_getClass("ASHideView");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"initWithFrame:"), (IMP)dummy_init_hidden);
        }

        cls = objc_getClass("ASStatusUDIDAlertView");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"configureWithTitle:message:leftTitle:rightTitle:"), (IMP)dummy_imp);
        }

        // --- 5d. Mute các lớp HUD xoay tròn (JGProgressHUD, MBProgressHUD, ASProgressHUD) ---
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
            NSLog(@"[LQBypass] ✅ Keychain UDID faked");
        }

        // --- 5g. Hook NetTool Fake Response ---
        Class netToolCls = objc_getClass("NetTool");
        if (netToolCls) {
            Method m1 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"));
            if (m1) {
                swizzleMethod(netToolCls, NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"), method_getImplementation(m1));
            }
            Method m2 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"));
            if (m2) {
                swizzleMethod(netToolCls, NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"), method_getImplementation(m2));
            }
            NSLog(@"[LQBypass] ✅ NetTool VIP responses installed");
        }

        NSLog(@"[LQBypass] ✅ Toàn bộ Swizzle hoàn tất thành công!");
    });
}

// -------------------------------------------------------------------------
// 6. Khởi tạo Mod Menu
// -------------------------------------------------------------------------
void bootstrap_mod_menu(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LQBypass] 🚀 Bắt đầu khởi tạo Menu Mod...");
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

        // Dọn dẹp overlay ngay sau khi tạo menu
        [LQBypassHelper forceCleanAllOverlays];
        [LQBypassHelper dismissAllHUDsAndWindows];
    });
}

// -------------------------------------------------------------------------
// 7. Constructor (Nạp Dylib khi app mở)
// -------------------------------------------------------------------------
__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] ⚡ Dylib v5.0 (Ultimate VIP) đã nạp thành công!");

    // Thực hiện swizzle ngay lập tức
    perform_swizzles();

    // Lắng nghe notification khởi động của App
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] 📱 UIApplicationDidFinishLaunchingNotification nhận được");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            bootstrap_mod_menu();
        });
    }];

    // Fallback kích hoạt sau 2.5 giây
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        bootstrap_mod_menu();
    });

    // Thêm cử chỉ toggle dự phòng: 2 ngón tay chạm 2 lần
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin && [UIApplication sharedApplication].windows.count > 0)
            keyWin = [UIApplication sharedApplication].windows.firstObject;
        if (keyWin) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                           initWithTarget:[LQBypassHelper class]
                                           action:@selector(toggleImGuiMenu)];
            tap.numberOfTouchesRequired = 2;
            tap.numberOfTapsRequired = 2;
            [keyWin addGestureRecognizer:tap];
        }
    });
}
