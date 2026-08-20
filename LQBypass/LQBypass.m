// =========================================================================
//  LQBypass.m — Tweak Dylib Hook cho Liên Quân Mobile iOS Mod (AWSS3)
//  Phiên bản 4.0: Cập nhật dựa trên báo cáo phân tích toàn diện Crypto & Network
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
// 2. Class Helper: Quản lý Menu Mod và Dọn dẹp triệt để màn hình mờ/đen
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)toggleImGuiMenu;
+ (void)dismissAllOverlays;
+ (void)bootstrapModMenu;
@end

@implementation LQBypassHelper

+ (void)dismissAllOverlays {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            NSString *winCls = NSStringFromClass([w class]);
            
            // Vô hiệu hóa toàn bộ cửa sổ phụ hiển thị auth / UDID
            if ([winCls containsString:@"APIClientOverlay"] ||
                [winCls containsString:@"OverlayWindow"] ||
                [winCls containsString:@"Status"]) {
                w.hidden = YES;
                w.alpha = 0.0;
                [w setRootViewController:nil];
                [w removeFromSuperview];
            }
            
            // Dọn dẹp toàn bộ view làm mờ (dimming / blur / HUD)
            for (UIView *subview in [w.subviews copy]) {
                NSString *cls = NSStringFromClass([subview class]);
                
                // Giữ nguyên ImGuiDrawView và Floating Buttons của Mod
                if ([cls containsString:@"ImGui"] || 
                    [cls containsString:@"Toggle"] || 
                    [cls containsString:@"Button"]) {
                    continue;
                }
                
                // Xóa sổ toàn bộ view che màn hình
                if ([cls containsString:@"HUD"] ||
                    [cls containsString:@"Status"] ||
                    [cls containsString:@"Alert"] ||
                    [cls containsString:@"HideView"] ||
                    [cls containsString:@"Loading"] ||
                    [cls containsString:@"Progress"] ||
                    [cls containsString:@"Indicator"] ||
                    [cls containsString:@"VisualEffect"]) {
                    NSLog(@"[LQBypass] 🧹 Đã xoá view che màn hình: %@", cls);
                    subview.hidden = YES;
                    [subview removeFromSuperview];
                }
            }
        }
    });
}

+ (void)bootstrapModMenu {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LQBypass] 🚀 Bắt đầu khởi tạo Menu Mod...");
        
        Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!cls) {
            NSLog(@"[LQBypass] ❌ Không tìm thấy class tXGBBDJNKKzPYcSGmlav");
            return;
        }
        
        g_modControllerInstance = [[cls alloc] init];
        NSLog(@"[LQBypass] ✅ Đã tạo instance tXGBBDJNKKzPYcSGmlav: %@", g_modControllerInstance);

        // Lưu vào BSS cache của AWSS3 @ 0x36BDFD0
        uintptr_t slide = get_awss3_base_slide();
        if (slide > 0) {
            uintptr_t *cache = (uintptr_t *)(slide + 0x36BDFD0);
            *cache = (uintptr_t)g_modControllerInstance;
            NSLog(@"[LQBypass] ✅ Đã lưu vào BSS cache @ %p", cache);
        }

        // Kích hoạt cử chỉ và vẽ nút tròn nổi lên màn hình
        if ([g_modControllerInstance respondsToSelector:@selector(initTapGes)]) {
            [g_modControllerInstance performSelector:@selector(initTapGes)];
            NSLog(@"[LQBypass] ✅ Đã gọi [initTapGes] thành công!");
        } else if ([g_modControllerInstance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
            [g_modControllerInstance performSelector:@selector(setupFloatingToggleButtons)];
            NSLog(@"[LQBypass] ✅ Đã gọi [setupFloatingToggleButtons] thành công!");
        }
        
        // Dọn dẹp overlay sau khi tạo nút
        [LQBypassHelper dismissAllOverlays];
    });
}

+ (void)toggleImGuiMenu {
    Class imguiCls = objc_getClass("ImGuiDrawView");
    if (!imguiCls) return;
    
    SEL getSel = NSSelectorFromString(@"GmmtbwBOlBYaQRpBHDVm");
    SEL setSel = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
    if (![imguiCls respondsToSelector:getSel] || ![imguiCls respondsToSelector:setSel]) return;
    
    BOOL (*getVis)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    void (*setVis)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
    
    BOOL current = getVis(imguiCls, getSel);
    setVis(imguiCls, setSel, !current);
    NSLog(@"[LQBypass] 🔄 Toggle Menu ImGui: %d -> %d", current, !current);
}

@end

// -------------------------------------------------------------------------
// 3. Dummy IMPs & Custom Implementations
// -------------------------------------------------------------------------
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

// Intercept Post_AppendURL:myparameters:mysuccess:myfailure:
// Thay vì treo máy chờ mạng, ta kích hoạt hoàn tất ngay và khởi tạo menu
static void fake_post_append_url(id self, SEL _cmd, id url, id params, void (^mysuccess)(id), void (^myfailure)(id)) {
    NSLog(@"[LQBypass] 🌐 Chặn request POST tới: %@", url);
    dispatch_async(dispatch_get_main_queue(), ^{
        [LQBypassHelper bootstrapModMenu];
        [LQBypassHelper dismissAllOverlays];
    });
}

// -------------------------------------------------------------------------
// 4. Cài đặt toàn bộ Swizzle theo tài liệu phân tích
// -------------------------------------------------------------------------
void perform_swizzles(void) {
    // 4a. Hook NetTool Post_AppendURL (Tránh treo mạng State Machine)
    Class netTool = objc_getClass("NetTool");
    if (netTool) {
        SEL postSel = NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:");
        Method m = class_getClassMethod(netTool, postSel);
        if (m) {
            method_setImplementation(m, (IMP)fake_post_append_url);
            NSLog(@"[LQBypass] ✅ Đã hook NetTool Post_AppendURL");
        }
    }

    // 4b. Hook Cửa sổ Overlay hiển thị Device UDID ID Mode
    Class overlayWin = objc_getClass("APIClientOverlayWindow");
    if (overlayWin) {
        Method m1 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"makeKeyAndVisible"));
        if (m1) method_setImplementation(m1, (IMP)dummy_imp);
        
        Method m2 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"initWithFrame:"));
        if (m2) method_setImplementation(m2, (IMP)dummy_init_hidden);
        
        Method m3 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"updateFrame"));
        if (m3) method_setImplementation(m3, (IMP)dummy_imp);
    }

    // 4c. Hook toàn bộ các điểm gọi Dialog của ASStatusView
    Class statusView = objc_getClass("ASStatusView");
    if (statusView) {
        NSArray *selectorsToMute = @[
            @"showLoginForm",
            @"showLoginFormWithTitle:description:placeholder:submitTitle:contactTitle:countdownFrom:",
            @"showExpiredForm",
            @"showExpiredWithTitle:message:changeKeyTitle:copyUDIDTitle:copyKeyTitle:countdownFrom:",
            @"showLoginError:",
            @"showLoginLoading",
            @"showUDIDAlertWithTitle:message:leftTitle:rightTitle:leftAction:rightAction:",
            @"layoutLoginForm:centerX:centerY:isLandscape:",
            @"layoutExpiredForm:centerX:centerY:isLandscape:",
            @"showSuccessWithTitle:message:",
            @"showErrorWithTitle:message:",
            @"showLoadingWithTitle:message:",
            @"showErrorWithTitle:message:buttonTitle:",
            @"showSuccessWithTitle:message:buttonTitle:"
        ];
        for (NSString *selName in selectorsToMute) {
            SEL sel = NSSelectorFromString(selName);
            Method m = class_getInstanceMethod(statusView, sel);
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
    }

    // 4d. Hook ASHideView & ASStatusUDIDAlertView
    Class hideView = objc_getClass("ASHideView");
    if (hideView) {
        Method m = class_getInstanceMethod(hideView, NSSelectorFromString(@"initWithFrame:"));
        if (m) method_setImplementation(m, (IMP)dummy_init_hidden);
    }
    
    Class udidAlert = objc_getClass("ASStatusUDIDAlertView");
    if (udidAlert) {
        Method m = class_getInstanceMethod(udidAlert, NSSelectorFromString(@"configureWithTitle:message:leftTitle:rightTitle:"));
        if (m) method_setImplementation(m, (IMP)dummy_imp);
    }

    // 4e. Mute JGProgressHUD & MBProgressHUD
    Class jgHud = objc_getClass("JGProgressHUD");
    if (jgHud) {
        for (NSString *selName in @[@"showInView:", @"showInView:animated:", @"showInView:animated:afterDelay:"]) {
            Method m = class_getInstanceMethod(jgHud, NSSelectorFromString(selName));
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
    }
    
    Class mbHud = objc_getClass("MBProgressHUD");
    if (mbHud) {
        for (NSString *selName in @[@"showAnimated:", @"showUsingAnimation:"]) {
            Method m = class_getInstanceMethod(mbHud, NSSelectorFromString(selName));
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
    }

    // 4f. Hook Keychain UDID
    Class keychain = objc_getClass("VKKeychainIDFV");
    if (!keychain) keychain = objc_getClass("VKKeychainUDID");
    if (keychain) {
        SEL getSel = sel_registerName("VKgetUdidFromKeyChain");
        Method gm = class_getClassMethod(keychain, getSel);
        if (!gm) gm = class_getInstanceMethod(keychain, getSel);
        if (gm) method_setImplementation(gm, (IMP)fake_udid_imp);

        SEL mainUdidSel = sel_registerName("VKKeychainUDID");
        Method um = class_getClassMethod(keychain, mainUdidSel);
        if (!um) um = class_getInstanceMethod(keychain, mainUdidSel);
        if (um) method_setImplementation(um, (IMP)fake_udid_imp);
    }
}

// -------------------------------------------------------------------------
// 5. Entry point (Constructor nạp dylib)
// -------------------------------------------------------------------------
__attribute__((constructor))
static void lq_bypass_init(void) {
    NSLog(@"[LQBypass] ⚡ Dylib v4.0 đã nạp thành công!");

    dispatch_async(dispatch_get_main_queue(), ^{
        perform_swizzles();
    });

    // Lắng nghe khi app khởi động xong
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] 📱 App hoàn tất khởi chạy!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper bootstrapModMenu];
            [LQBypassHelper dismissAllOverlays];
        });
    }];

    // Fallback kích hoạt sau 2.5 giây
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LQBypassHelper bootstrapModMenu];
        [LQBypassHelper dismissAllOverlays];
    });

    // Quét liên tục dọn sạch màn hình mờ trong 8 giây đầu
    for (float delay = 0.5; delay <= 8.0; delay += 0.5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper dismissAllOverlays];
        });
    }

    // Cử chỉ dự phòng: 2 ngón tay chạm 2 lần để bật/tắt Menu ImGui
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        if (keyWindow) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                            initWithTarget:[LQBypassHelper class]
                                            action:@selector(toggleImGuiMenu)];
            tap.numberOfTouchesRequired = 2;
            tap.numberOfTapsRequired = 2;
            [keyWindow addGestureRecognizer:tap];
        }
    });
}
