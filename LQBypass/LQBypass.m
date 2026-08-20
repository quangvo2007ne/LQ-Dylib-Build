#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// =========================================================================
//  LQBypass_fixed_v2.m — Tweak Dylib mạnh tay cho AWSS3
// =========================================================================

static id g_modControllerInstance = nil;

// -------------------------------------------------------------------------
// 1. Helper tìm slide AWSS3
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
// 2. Helper for Menu & Cleanup
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
        // Giữ lại ImGui và các nút toggle
        if ([cls containsString:@"ImGui"] || [cls containsString:@"Toggle"] || [cls containsString:@"Button"]) {
            continue;
        }
        // Loại bỏ mọi HUD, status, alert, loading, visual effect (làm mờ)
        if ([cls containsString:@"HUD"] || [cls containsString:@"Status"] ||
            [cls containsString:@"Alert"] || [cls containsString:@"Loading"] ||
            [cls containsString:@"Progress"] || [cls containsString:@"Indicator"] ||
            [cls containsString:@"HideView"] || [cls containsString:@"VisualEffect"]) {
            v.hidden = YES;
            [v removeFromSuperview];
        } else {
            // Đệ quy quét sạch tất cả các cấp view con
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
    // Chạy dọn dẹp quét liên tục trong 5 giây đầu
    for (int i = 0; i < 15; i++) {
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
    NSLog(@"[LQBypass] 🔄 Toggle ImGui: %d -> %d", current, !current);
}
@end

// -------------------------------------------------------------------------
// 3. Fake NetTool response
// -------------------------------------------------------------------------
@interface NetToolFake : NSObject
+ (id)Post_AppendURL:(id)url myparameters:(id)params mysuccess:(id)success myfailure:(id)failure;
+ (BOOL)verifySignature:(id)signature withData:(id)data usingPublicKeyString:(id)key;
@end

@implementation NetToolFake

+ (id)Post_AppendURL:(id)url myparameters:(id)params mysuccess:(id)success myfailure:(id)failure {
    NSString *urlStr = [url description];
    NSLog(@"[LQBypass] 🌐 NetTool POST: %@", urlStr);

    if ([urlStr containsString:@"package-v3"] || [urlStr containsString:@"key-v3"] || [urlStr containsString:@"credential-v3"]) {
        NSLog(@"[LQBypass] 🎯 Fake response cho auth endpoint: %@", urlStr);
        NSDictionary *fakeResponse = @{
            @"code": @200,
            @"msg": @"OK",
            @"data": @{}
        };
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    void (^succBlock)(id) = (void (^)(id))success;
                    succBlock(fakeResponse);
                } @catch (NSException *e) {
                    NSLog(@"[LQBypass] Exception calling success block: %@", e);
                }
            });
        }
        return nil;
    }
    return nil;
}

+ (BOOL)verifySignature:(id)signature withData:(id)data usingPublicKeyString:(id)key {
    return YES;
}
@end

// -------------------------------------------------------------------------
// 4. Swizzle utilities
// -------------------------------------------------------------------------
void swizzleMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, newImp);
}

// Các IMP thay thế
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

static void dummy_showHUD(id self, SEL _cmd, ...) {
    // Không làm gì, chặn hiển thị HUD
}

// -------------------------------------------------------------------------
// 5. Thực hiện swizzle
// -------------------------------------------------------------------------
void perform_swizzles(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // --- APIClientOverlayWindow ---
        Class cls = objc_getClass("APIClientOverlayWindow");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"makeKeyAndVisible"), (IMP)dummy_imp);
            swizzleMethod(cls, NSSelectorFromString(@"initWithFrame:"), (IMP)dummy_init_hidden);
            NSLog(@"[LQBypass] ✅ OverlayWindow swizzled");
        }

        // --- ASStatusView ---
        cls = objc_getClass("ASStatusView");
        if (cls) {
            NSArray *selList = @[
                @"showLoginForm", @"showExpiredForm", @"showLoginError:",
                @"showLoginLoading", @"showUDIDAlertWithTitle:message:leftTitle:rightTitle:leftAction:rightAction:",
                @"showLoadingWithTitle:message:", @"showSuccessWithTitle:message:", @"showErrorWithTitle:message:",
                @"layoutLoginForm:centerX:centerY:isLandscape:", @"layoutExpiredForm:centerX:centerY:isLandscape:"
            ];
            for (NSString *selName in selList) {
                SEL sel = NSSelectorFromString(selName);
                if (sel) swizzleMethod(cls, sel, (IMP)dummy_imp);
            }
            NSLog(@"[LQBypass] ✅ ASStatusView swizzled");
        }

        // --- ASHideView ---
        cls = objc_getClass("ASHideView");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"initWithFrame:"), (IMP)dummy_init_hidden);
        }

        // --- ASStatusUDIDAlertView ---
        cls = objc_getClass("ASStatusUDIDAlertView");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"configureWithTitle:message:leftTitle:rightTitle:"), (IMP)dummy_imp);
        }

        // --- HUDs (JGProgressHUD) ---
        cls = objc_getClass("JGProgressHUD");
        if (cls) {
            NSArray *selList = @[@"showInView:", @"showInView:animated:", @"showInView:animated:afterDelay:"];
            for (NSString *selName in selList) {
                SEL sel = NSSelectorFromString(selName);
                if (sel) swizzleMethod(cls, sel, (IMP)dummy_showHUD);
            }
            NSLog(@"[LQBypass] ✅ JGProgressHUD muted");
        }

        // --- MBProgressHUD ---
        cls = objc_getClass("MBProgressHUD");
        if (cls) {
            NSArray *selList = @[@"showAnimated:", @"showUsingAnimation:"];
            for (NSString *selName in selList) {
                SEL sel = NSSelectorFromString(selName);
                if (sel) swizzleMethod(cls, sel, (IMP)dummy_showHUD);
            }
            NSLog(@"[LQBypass] ✅ MBProgressHUD muted");
        }

        // --- ASProgressHUD ---
        cls = objc_getClass("ASProgressHUD");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"show:"), (IMP)dummy_showHUD);
            swizzleMethod(cls, NSSelectorFromString(@"showUsingAnimation:"), (IMP)dummy_showHUD);
            NSLog(@"[LQBypass] ✅ ASProgressHUD muted");
        }

        // --- ASIndicator ---
        cls = objc_getClass("ASIndicator");
        if (cls) {
            NSArray *selList = @[
                @"showNotificationWithTitle:message:",
                @"showNotificationWithTitle:message:tapHandler:",
                @"showNotificationWithTitle:message:tapHandler:completion:",
                @"showNotificationWithImage:title:message:"
            ];
            for (NSString *selName in selList) {
                SEL sel = NSSelectorFromString(selName);
                if (sel) swizzleMethod(cls, sel, (IMP)dummy_imp);
            }
            NSLog(@"[LQBypass] ✅ ASIndicator muted");
        }

        // --- Keychain UDID fake ---
        cls = objc_getClass("VKKeychainUDID");
        if (!cls) cls = objc_getClass("VKKeychainIDFV");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"VKgetUdidFromKeyChain"), (IMP)fake_udid_imp);
            swizzleMethod(cls, NSSelectorFromString(@"VKsaveUdidToKeyChain:"), (IMP)dummy_save_udid);
            NSLog(@"[LQBypass] ✅ Keychain UDID faked");
        }

        // --- NetTool fake ---
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
            NSLog(@"[LQBypass] ✅ NetTool faked");
        }

        NSLog(@"[LQBypass] perform_swizzles completed");
    });
}

// -------------------------------------------------------------------------
// 6. Bootstrap mod menu
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

        // Ghi vào BSS cache
        uintptr_t slide = get_awss3_base_slide();
        if (slide) {
            uintptr_t *cache_ptr = (uintptr_t *)(slide + 0x36BDFD0);
            *cache_ptr = (uintptr_t)g_modControllerInstance;
            NSLog(@"[LQBypass] ✅ Đã ghi instance vào BSS cache @ %p", cache_ptr);
        }

        // Gọi initTapGes nếu có
        if ([g_modControllerInstance respondsToSelector:@selector(initTapGes)]) {
            [g_modControllerInstance performSelector:@selector(initTapGes)];
            NSLog(@"[LQBypass] ✅ Đã gọi [initTapGes]");
        } else if ([g_modControllerInstance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
            [g_modControllerInstance performSelector:@selector(setupFloatingToggleButtons)];
            NSLog(@"[LQBypass] ✅ Đã gọi [setupFloatingToggleButtons]");
        }

        // Dọn dẹp ngay sau khi menu xuất hiện
        [LQBypassHelper forceCleanAllOverlays];
        [LQBypassHelper dismissAllHUDsAndWindows];
    });
}

// -------------------------------------------------------------------------
// 7. Constructor
// -------------------------------------------------------------------------
__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] Dylib loaded (constructor)");

    // In danh sách class để kiểm tra nếu cần
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);
        for (int i = 0; i < numClasses; i++) {
            const char *name = class_getName(classes[i]);
            if (name && (strstr(name, "Overlay") || strstr(name, "Status") || strstr(name, "HUD"))) {
                NSLog(@"[LQBypass] 🔎 Found overlay class: %s", name);
            }
        }
        free(classes);
    }

    // Swizzle ngay khi load
    perform_swizzles();

    // Đăng ký notification khi app finish launch
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] UIApplicationDidFinishLaunchingNotification received");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            bootstrap_mod_menu();
        });
    }];

    // Fallback sau 2.5 giây
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        bootstrap_mod_menu();
    });

    // Thêm gesture toggle dự phòng (2 ngón 2 lần)
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
