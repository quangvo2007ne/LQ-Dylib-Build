#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// =========================================================================
//  LQBypass.m — Tweak Dylib Hook cho Liên Quân Mobile iOS Mod (AWSS3)
//  Tác giả: Reverse Engineering Assistant & User
//  Version 3.0: Vô hiệu hóa triệt để APIClientOverlayWindow & UDID Spinner
// =========================================================================

static id g_modControllerInstance = nil;

// -------------------------------------------------------------------------
// 1. Helper tìm Image Base của AWSS3
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
// 2. Class Helper cho Menu & Dọn Dẹp Toàn Bộ Cửa Sổ Overlay Chặn Màn Hình
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)toggleImGuiMenu;
+ (void)dismissAllHUDsAndWindows;
@end

@implementation LQBypassHelper

+ (void)dismissAllHUDsAndWindows {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. Quét và ẩn toàn bộ cửa sổ phụ (APIClientOverlayWindow)
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *w in windows) {
            NSString *winCls = NSStringFromClass([w class]);
            if ([winCls containsString:@"APIClientOverlay"] || [winCls containsString:@"OverlayWindow"] || [winCls containsString:@"Status"]) {
                NSLog(@"[LQBypass] 🚫 Ẩn hoàn toàn cửa sổ phụ: %@", winCls);
                w.hidden = YES;
                w.alpha = 0.0;
                [w setRootViewController:nil];
            }
            
            // 2. Quét đệ quy tất cả view con để dọn sạch
            for (UIView *subview in [w.subviews copy]) {
                NSString *className = NSStringFromClass([subview class]);
                // Không ẩn ImGuiDrawView và Floating Buttons
                if ([className containsString:@"ImGui"] || 
                    [className containsString:@"Toggle"] || 
                    [className containsString:@"Button"]) {
                    continue;
                }
                if ([className containsString:@"HUD"] || 
                    [className containsString:@"Status"] || 
                    [className containsString:@"Alert"] || 
                    [className containsString:@"HideView"] ||
                    [className containsString:@"Loading"] ||
                    [className containsString:@"Progress"] ||
                    [className containsString:@"Indicator"]) {
                    NSLog(@"[LQBypass] 🧹 Đã xoá view chặn màn hình: %@", className);
                    subview.hidden = YES;
                    [subview removeFromSuperview];
                }
            }
        }
    });
}

+ (void)toggleImGuiMenu {
    Class imguiCls = objc_getClass("ImGuiDrawView");
    if (!imguiCls) {
        NSLog(@"[LQBypass] ❌ Không tìm thấy ImGuiDrawView");
        return;
    }
    SEL getVisSel = NSSelectorFromString(@"GmmtbwBOlBYaQRpBHDVm");
    SEL setVisSel = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
    if (![imguiCls respondsToSelector:getVisSel] || ![imguiCls respondsToSelector:setVisSel]) {
        NSLog(@"[LQBypass] ⚠️ Không tìm thấy selector toggle");
        return;
    }
    BOOL (*getVis)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    void (*setVis)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
    BOOL current = getVis(imguiCls, getVisSel);
    setVis(imguiCls, setVisSel, !current);
    NSLog(@"[LQBypass] 🔄 Toggle ImGui Menu: %d → %d", current, !current);
}

@end

// -------------------------------------------------------------------------
// 3. Hàm khởi tạo Menu Mod (tạo nút tròn nổi)
// -------------------------------------------------------------------------
void bootstrap_mod_menu(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LQBypass] Bắt đầu khởi tạo Menu Mod...");

        Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!cls) {
            NSLog(@"[LQBypass] ❌ Không tìm thấy class tXGBBDJNKKzPYcSGmlav");
            return;
        }

        g_modControllerInstance = [[cls alloc] init];
        NSLog(@"[LQBypass] ✅ Đã tạo instance: %@", g_modControllerInstance);

        uintptr_t slide = get_awss3_base_slide();
        if (slide > 0) {
            uintptr_t *cache_ptr = (uintptr_t *)(slide + 0x36BDFD0);
            *cache_ptr = (uintptr_t)g_modControllerInstance;
            NSLog(@"[LQBypass] ✅ Đã ghi instance vào BSS cache @ %p", cache_ptr);
        }

        if ([g_modControllerInstance respondsToSelector:@selector(initTapGes)]) {
            [g_modControllerInstance performSelector:@selector(initTapGes)];
            NSLog(@"[LQBypass] ✅ Đã gọi [initTapGes]");
        } else if ([g_modControllerInstance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
            [g_modControllerInstance performSelector:@selector(setupFloatingToggleButtons)];
            NSLog(@"[LQBypass] ✅ Đã gọi [setupFloatingToggleButtons]");
        }
    });
}

// -------------------------------------------------------------------------
// 4. Các hàm C thay thế cho swizzling
// -------------------------------------------------------------------------

static void dummy_imp(id self, SEL _cmd, ...) {
    // Không làm gì cả
}

static id dummy_init_hidden_imp(id self, SEL _cmd, CGRect frame) {
    UIView *v = ((UIView *(*)(id, SEL, CGRect))objc_msgSendSuper)(self, _cmd, frame);
    if ([v isKindOfClass:[UIWindow class]] || [v isKindOfClass:[UIView class]]) {
        v.hidden = YES;
        v.alpha = 0.0;
    }
    return v;
}

static id fake_udid_imp(id self, SEL _cmd) {
    return @"00000000-0000-0000-0000-000000000000";
}

static void dummy_save_udid_imp(id self, SEL _cmd, id udid) {
}

// -------------------------------------------------------------------------
// 5. Thực hiện swizzle chặn toàn bộ cửa sổ và popup UDID / Key
// -------------------------------------------------------------------------
void perform_swizzles(void) {
    // --- 5a. Chặn APIClientOverlayWindow (Cửa sổ hiển thị Device UDID ID Mode) ---
    Class overlayWinCls = objc_getClass("APIClientOverlayWindow");
    if (overlayWinCls) {
        Method makeKeyM = class_getInstanceMethod(overlayWinCls, NSSelectorFromString(@"makeKeyAndVisible"));
        if (makeKeyM) method_setImplementation(makeKeyM, (IMP)dummy_imp);
        
        Method initM = class_getInstanceMethod(overlayWinCls, NSSelectorFromString(@"initWithFrame:"));
        if (initM) method_setImplementation(initM, (IMP)dummy_init_hidden_imp);
        
        NSLog(@"[LQBypass] ✅ Đã vô hiệu hoá APIClientOverlayWindow!");
    }
    
    // --- 5b. Chặn ASHideView & ASStatusUDIDAlertView ---
    Class hideViewCls = objc_getClass("ASHideView");
    if (hideViewCls) {
        Method initM = class_getInstanceMethod(hideViewCls, NSSelectorFromString(@"initWithFrame:"));
        if (initM) method_setImplementation(initM, (IMP)dummy_init_hidden_imp);
    }
    
    Class udidAlertCls = objc_getClass("ASStatusUDIDAlertView");
    if (udidAlertCls) {
        Method confM = class_getInstanceMethod(udidAlertCls, NSSelectorFromString(@"configureWithTitle:message:leftTitle:rightTitle:"));
        if (confM) method_setImplementation(confM, (IMP)dummy_imp);
    }

    // --- 5c. Vô hiệu hoá các popup của ASStatusView ---
    Class statusViewCls = objc_getClass("ASStatusView");
    if (statusViewCls) {
        NSArray *selectorsToMute = @[
            @"showLoginForm",
            @"showLoginFormWithTitle:description:placeholder:submitTitle:contactTitle:countdownFrom:",
            @"showExpiredForm",
            @"showExpiredWithTitle:message:changeKeyTitle:copyUDIDTitle:copyKeyTitle:countdownFrom:",
            @"showLoginError:",
            @"showLoginLoading",
            @"showUDIDAlertWithTitle:message:leftTitle:rightTitle:leftAction:rightAction:",
            @"layoutLoginForm:centerX:centerY:isLandscape:",
            @"layoutExpiredForm:centerX:centerY:isLandscape:"
        ];
        for (NSString *selName in selectorsToMute) {
            SEL sel = NSSelectorFromString(selName);
            Method m = class_getInstanceMethod(statusViewCls, sel);
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
    }

    // --- 5d. Mute JGProgressHUD & MBProgressHUD ---
    Class jgHudCls = objc_getClass("JGProgressHUD");
    if (jgHudCls) {
        for (NSString *selName in @[@"showInView:", @"showInView:animated:", @"showInView:animated:afterDelay:"]) {
            Method m = class_getInstanceMethod(jgHudCls, NSSelectorFromString(selName));
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
    }
    
    Class mbHudCls = objc_getClass("MBProgressHUD");
    if (mbHudCls) {
        for (NSString *selName in @[@"showAnimated:", @"showUsingAnimation:"]) {
            Method m = class_getInstanceMethod(mbHudCls, NSSelectorFromString(selName));
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
    }

    // --- 5e. Hook VKKeychainUDID ---
    Class keychainCls = objc_getClass("VKKeychainUDID");
    if (!keychainCls) keychainCls = objc_getClass("VKKeychainIDFV");
    if (keychainCls) {
        SEL sel = sel_registerName("VKgetUdidFromKeyChain");
        Method m = class_getClassMethod(keychainCls, sel);
        if (!m) m = class_getInstanceMethod(keychainCls, sel);
        if (m) method_setImplementation(m, (IMP)fake_udid_imp);

        SEL saveSel = sel_registerName("VKsaveUdidToKeyChain:");
        Method saveM = class_getClassMethod(keychainCls, saveSel);
        if (!saveM) saveM = class_getInstanceMethod(keychainCls, saveSel);
        if (saveM) method_setImplementation(saveM, (IMP)dummy_save_udid_imp);
    }
}

// -------------------------------------------------------------------------
// 6. Entry point – Constructor
// -------------------------------------------------------------------------
__attribute__((constructor))
static void lq_bypass_init(void) {
    NSLog(@"[LQBypass] Tweak dylib đã được nạp vào tiến trình!");

    dispatch_async(dispatch_get_main_queue(), ^{
        perform_swizzles();
    });

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] 📱 UIApplicationDidFinishLaunchingNotification nhận được!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            bootstrap_mod_menu();
            [LQBypassHelper dismissAllHUDsAndWindows];
        });
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        bootstrap_mod_menu();
        [LQBypassHelper dismissAllHUDsAndWindows];
    });

    // Quét liên tục dọn sạch trong 10 giây đầu khởi động
    for (float delay = 0.5; delay <= 10.0; delay += 0.5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper dismissAllHUDsAndWindows];
        });
    }

    // Cử chỉ dự phòng: 2 ngón chạm 2 lần để toggle Menu Mod ImGui
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow && [[UIApplication sharedApplication].windows count] > 0) {
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
