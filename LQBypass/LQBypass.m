// LQBypass.m – Full bypass for Liên Quân Mobile AWSS3 mod
// Version 3.1 – Fixed all identified gaps & safe objc_super handling

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// =========================================================================
//  Helper: Get AWSS3 slide
// =========================================================================
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

// =========================================================================
//  Helper class to manage UI and menu
// =========================================================================
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
            if ([winCls containsString:@"APIClientOverlay"] ||
                [winCls containsString:@"OverlayWindow"] ||
                [winCls containsString:@"Status"]) {
                w.hidden = YES;
                w.alpha = 0.0;
                [w setRootViewController:nil];
            }
            // Remove any stray HUD/Alert views
            for (UIView *subview in [w.subviews copy]) {
                NSString *cls = NSStringFromClass([subview class]);
                // Không ẩn ImGui và Floating Buttons
                if ([cls containsString:@"ImGui"] || [cls containsString:@"Toggle"] || [cls containsString:@"Button"]) {
                    continue;
                }
                if ([cls containsString:@"HUD"] ||
                    [cls containsString:@"Status"] ||
                    [cls containsString:@"Alert"] ||
                    [cls containsString:@"HideView"] ||
                    [cls containsString:@"Loading"] ||
                    [cls containsString:@"Progress"] ||
                    [cls containsString:@"Indicator"]) {
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
        NSLog(@"[LQBypass] Bootstrapping mod menu...");
        Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!cls) {
            NSLog(@"[LQBypass] ❌ Class tXGBBDJNKKzPYcSGmlav not found");
            return;
        }
        id instance = [[cls alloc] init];
        if (!instance) {
            NSLog(@"[LQBypass] ❌ Failed to alloc instance");
            return;
        }

        // Store in BSS cache as original does
        uintptr_t slide = get_awss3_base_slide();
        if (slide) {
            uintptr_t *cache = (uintptr_t *)(slide + 0x36BDFD0);
            *cache = (uintptr_t)instance;
        }

        if ([instance respondsToSelector:@selector(initTapGes)]) {
            [instance performSelector:@selector(initTapGes)];
            NSLog(@"[LQBypass] ✅ initTapGes called");
        } else if ([instance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
            [instance performSelector:@selector(setupFloatingToggleButtons)];
            NSLog(@"[LQBypass] ✅ setupFloatingToggleButtons called");
        }
        
        // Clean overlays again
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
    NSLog(@"[LQBypass] Toggle ImGui menu: %d -> %d", current, !current);
}

@end

// =========================================================================
//  Dummy IMPs
// =========================================================================
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

// =========================================================================
//  Swizzles
// =========================================================================
void perform_swizzles(void) {
    // 1. Block network request
    Class netTool = objc_getClass("NetTool");
    if (netTool) {
        SEL postSel = NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:");
        Method m = class_getClassMethod(netTool, postSel);
        if (m) method_setImplementation(m, (IMP)dummy_imp);
    }

    // 2. Block FWEncryptorAES decrypt
    Class fwEnc = objc_getClass("FWEncryptorAES");
    if (fwEnc) {
        SEL decSel = NSSelectorFromString(@"decrypt:Key:IV:");
        Method m = class_getClassMethod(fwEnc, decSel);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^id(id self, NSData *cipher, NSData *key, NSData *iv) {
                NSLog(@"[LQBypass] Bypassing FWEncryptorAES decrypt");
                return [[NSData alloc] init];
            });
            method_setImplementation(m, newImp);
        }
    }

    // 3. Overlay windows
    Class overlayWin = objc_getClass("APIClientOverlayWindow");
    if (overlayWin) {
        Method m1 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"makeKeyAndVisible"));
        if (m1) method_setImplementation(m1, (IMP)dummy_imp);
        Method m2 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"initWithFrame:"));
        if (m2) method_setImplementation(m2, (IMP)dummy_init_hidden);
        Method m3 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"updateFrame"));
        if (m3) method_setImplementation(m3, (IMP)dummy_imp);
    }

    // 4. ASStatusView (all possible UI entries)
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

    // 5. Hide views
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

    // 6. HUDs (JGProgressHUD and MBProgressHUD)
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

    // 7. UDID keychain
    Class keychain = objc_getClass("VKKeychainUDID");
    if (!keychain) keychain = objc_getClass("VKKeychainIDFV");
    if (keychain) {
        SEL getSel = sel_registerName("VKgetUdidFromKeyChain");
        Method gm = class_getClassMethod(keychain, getSel);
        if (!gm) gm = class_getInstanceMethod(keychain, getSel);
        if (gm) method_setImplementation(gm, (IMP)fake_udid_imp);

        SEL saveSel = sel_registerName("VKsaveUdidToKeyChain:");
        Method sm = class_getClassMethod(keychain, saveSel);
        if (!sm) sm = class_getInstanceMethod(keychain, saveSel);
        if (sm) method_setImplementation(sm, (IMP)dummy_save_udid);
    }
}

// =========================================================================
//  Entry point
// =========================================================================
__attribute__((constructor))
static void lq_bypass_init(void) {
    NSLog(@"[LQBypass] Dylib loaded.");

    dispatch_async(dispatch_get_main_queue(), ^{
        perform_swizzles();
    });

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] App finished launching.");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper bootstrapModMenu];
            [LQBypassHelper dismissAllOverlays];
        });
    }];

    // Fallback: after 2.5 seconds if notification didn't fire
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LQBypassHelper bootstrapModMenu];
        [LQBypassHelper dismissAllOverlays];
    });

    // Sweeper to clean any HUDs appearing in the first 8 seconds
    for (float delay = 0.5; delay <= 8.0; delay += 0.5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper dismissAllOverlays];
        });
    }

    // Double-tap two fingers to toggle ImGui
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
