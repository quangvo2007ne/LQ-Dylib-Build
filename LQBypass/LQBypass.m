#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// =========================================================================
//  LQBypass.m — Tweak Dylib Hook cho Liên Quân Mobile iOS Mod (AWSS3)
//  Tác giả: Reverse Engineering Assistant & User
//  Version hoàn chỉnh – An toàn, không crash, tự động dọn sạch HUD
// =========================================================================

static id g_modControllerInstance = nil;

// -------------------------------------------------------------------------
// 1. Helper tìm Image Base của AWSS3 (dùng cho lưu BSS cache)
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
// 2. Class Helper cho Menu & HUD Cleanup
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)toggleImGuiMenu;
+ (void)dismissAllHUDs;
@end

@implementation LQBypassHelper

+ (void)dismissAllHUDs {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            for (UIView *subview in [window.subviews copy]) {
                NSString *className = NSStringFromClass([subview class]);
                // Không ẩn ImGuiDrawView và Floating Buttons
                if ([className containsString:@"ImGui"] || 
                    [className containsString:@"Toggle"] || 
                    [className containsString:@"Button"]) {
                    continue;
                }
                // Xóa toàn bộ HUD / Spinner / Alert che màn hình
                if ([className containsString:@"HUD"] || 
                    [className containsString:@"Status"] || 
                    [className containsString:@"Alert"] || 
                    [className containsString:@"Loading"] ||
                    [className containsString:@"Progress"]) {
                    NSLog(@"[LQBypass] 🧹 Đã xoá HUD che màn hình: %@", className);
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
// 3. Hàm khởi tạo Menu Mod (gọi sau khi UIWindow sẵn sàng)
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

        // Tạo instance và lưu vào biến tĩnh
        g_modControllerInstance = [[cls alloc] init];
        NSLog(@"[LQBypass] ✅ Đã tạo instance: %@", g_modControllerInstance);

        // Ghi vào BSS cache của AWSS3 (nếu có slide)
        uintptr_t slide = get_awss3_base_slide();
        if (slide > 0) {
            uintptr_t *cache_ptr = (uintptr_t *)(slide + 0x36BDFD0);
            *cache_ptr = (uintptr_t)g_modControllerInstance;
            NSLog(@"[LQBypass] ✅ Đã ghi instance vào BSS cache @ %p", cache_ptr);
        }

        // Gọi initTapGes và setupFloatingToggleButtons
        if ([g_modControllerInstance respondsToSelector:@selector(initTapGes)]) {
            [g_modControllerInstance performSelector:@selector(initTapGes)];
            NSLog(@"[LQBypass] ✅ Đã gọi [initTapGes]");
        } else if ([g_modControllerInstance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
            [g_modControllerInstance performSelector:@selector(setupFloatingToggleButtons)];
            NSLog(@"[LQBypass] ✅ Đã gọi [setupFloatingToggleButtons]");
        } else {
            NSLog(@"[LQBypass] ⚠️ Không tìm thấy initTapGes / setupFloatingToggleButtons");
        }
    });
}

// -------------------------------------------------------------------------
// 4. Các hàm C thay thế cho method swizzle (an toàn hơn block)
// -------------------------------------------------------------------------

// Hàm no-op cho các popup UDID/Key/HUD
static void dummy_imp(id self, SEL _cmd, ...) {
    NSLog(@"[LQBypass] Chặn popup: %@", NSStringFromSelector(_cmd));
}

// Hàm thay cho VKgetUdidFromKeyChain – trả về UDID giả
static id fake_udid_imp(id self, SEL _cmd) {
    NSLog(@"[LQBypass] VKgetUdidFromKeyChain → trả về UDID giả");
    return @"00000000-0000-0000-0000-000000000000";
}

// Hàm thay cho VKsaveUdidToKeyChain: – vô hiệu hoá ghi
static void dummy_save_udid_imp(id self, SEL _cmd, id udid) {
    NSLog(@"[LQBypass] VKsaveUdidToKeyChain: bị chặn (UDID: %@)", udid);
}

// -------------------------------------------------------------------------
// 5. Thực hiện swizzle tất cả các method cần thiết
// -------------------------------------------------------------------------
void perform_swizzles(void) {
    // --- 5a. Vô hiệu hoá các popup của ASStatusView ---
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
            if (m) {
                method_setImplementation(m, (IMP)dummy_imp);
                NSLog(@"[LQBypass] ✅ Đã mute ASStatusView: %@", selName);
            }
        }
    }

    // --- 5b. Mute JGProgressHUD & MBProgressHUD (Chặn triệt để spinner đứng hình) ---
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

    // --- 5c. Hook VKKeychainUDID ---
    Class keychainCls = objc_getClass("VKKeychainUDID");
    if (!keychainCls) keychainCls = objc_getClass("VKKeychainIDFV");
    if (keychainCls) {
        SEL sel = sel_registerName("VKgetUdidFromKeyChain");
        Method m = class_getClassMethod(keychainCls, sel);
        if (!m) m = class_getInstanceMethod(keychainCls, sel);
        if (m) {
            method_setImplementation(m, (IMP)fake_udid_imp);
            NSLog(@"[LQBypass] ✅ Đã hook VKgetUdidFromKeyChain");
        }

        SEL saveSel = sel_registerName("VKsaveUdidToKeyChain:");
        Method saveM = class_getClassMethod(keychainCls, saveSel);
        if (!saveM) saveM = class_getInstanceMethod(keychainCls, saveSel);
        if (saveM) {
            method_setImplementation(saveM, (IMP)dummy_save_udid_imp);
            NSLog(@"[LQBypass] ✅ Đã hook VKsaveUdidToKeyChain:");
        }
    }
}

// -------------------------------------------------------------------------
// 6. Entry point – Constructor
// -------------------------------------------------------------------------
__attribute__((constructor))
static void lq_bypass_init(void) {
    NSLog(@"[LQBypass] Tweak dylib đã được nạp vào tiến trình!");

    // 6a. Thực hiện swizzle ngay khi load
    dispatch_async(dispatch_get_main_queue(), ^{
        perform_swizzles();
    });

    // 6b. Lắng nghe UIApplicationDidFinishLaunchingNotification để khởi tạo menu
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] 📱 UIApplicationDidFinishLaunchingNotification nhận được!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            bootstrap_mod_menu();
        });
    }];

    // 6c. Dự phòng: nếu notification đã qua, vẫn khởi tạo sau 3 giây
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        bootstrap_mod_menu();
    });

    // 6d. Thêm cử chỉ dự phòng (2 ngón, 2 lần chạm) để toggle menu
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
            NSLog(@"[LQBypass] ✌️ Đã thêm cử chỉ dự phòng (2 ngón, 2 chạm)");
        }
    });

    // 6e. Lặp dọn dẹp sạch toàn bộ HUD quay quay sau 0.5s, 1s, 2s, 3s, 5s
    for (float delay = 0.5; delay <= 5.0; delay += 0.5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper dismissAllHUDs];
        });
    }
}
