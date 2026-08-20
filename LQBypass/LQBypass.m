// LQBypass_debug_final.m
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// === Helper viết log vào file ===
void writeLog(NSString *msg) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = paths.firstObject;
    NSString *logPath = [docDir stringByAppendingPathComponent:@"lq_bypass_log.txt"];
    NSString *timestamp = [NSDate date].description;
    NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fileHandle) {
        [entry writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

// === Helper hiện pop-up ===
void showAlert(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (keyWin && keyWin.rootViewController) {
            [keyWin.rootViewController presentViewController:alert animated:YES completion:nil];
        } else {
            NSArray *windows = [UIApplication sharedApplication].windows;
            if (windows.count > 0) {
                UIWindow *w = windows.firstObject;
                if (w.rootViewController) {
                    [w.rootViewController presentViewController:alert animated:YES completion:nil];
                }
            }
        }
    });
}

// === Get AWSS3 slide ===
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

// === Helper class ===
@interface LQBypassHelper : NSObject
+ (void)toggleImGuiMenu;
+ (void)dismissAllOverlays;
+ (void)bootstrapModMenu;
@end

@implementation LQBypassHelper

+ (void)dismissAllOverlays {
    dispatch_async(dispatch_get_main_queue(), ^{
        writeLog(@"dismissAllOverlays called");
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
            for (UIView *subview in [w.subviews copy]) {
                NSString *cls = NSStringFromClass([subview class]);
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
        writeLog(@"bootstrapModMenu started");
        showAlert(@"LQBypass", @"Đang tìm class mod...");

        // 1. Tìm class "tXGBBDJNKKzPYcSGmlav"
        Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (cls) {
            writeLog(@"✅ Tìm thấy class tXGBBDJNKKzPYcSGmlav");
            showAlert(@"Thành công", @"Tìm thấy class mod!");
        } else {
            writeLog(@"❌ Không tìm thấy class tXGBBDJNKKzPYcSGmlav");
            showAlert(@"Thất bại", @"Không tìm thấy class mod! Đang tìm class khác...");
        }

        // 2. Nếu không tìm thấy, tự động quét tất cả class để tìm
        if (!cls) {
            int numClasses = objc_getClassList(NULL, 0);
            if (numClasses > 0) {
                Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
                numClasses = objc_getClassList(classes, numClasses);
                NSMutableArray *foundClasses = [NSMutableArray array];
                for (int i = 0; i < numClasses; i++) {
                    const char *name = class_getName(classes[i]);
                    if (name) {
                        NSString *nsName = [NSString stringWithUTF8String:name];
                        // Tìm class có chứa từ khóa "ImGui", "Draw", "Toggle" hoặc bắt đầu bằng "tX"
                        if ([nsName containsString:@"ImGui"] ||
                            [nsName containsString:@"DrawView"] ||
                            [nsName containsString:@"Toggle"] ||
                            [nsName hasPrefix:@"tX"]) {
                            [foundClasses addObject:nsName];
                            writeLog([NSString stringWithFormat:@"Tìm thấy class tiềm năng: %@", nsName]);
                        }
                    }
                }
                free(classes);
                
                if (foundClasses.count > 0) {
                    NSString *msg = [foundClasses componentsJoinedByString:@"\n"];
                    writeLog([NSString stringWithFormat:@"Danh sách class tìm thấy:\n%@", msg]);
                    showAlert(@"Class tìm thấy", msg);
                } else {
                    writeLog(@"❌ Không tìm thấy class nào có từ khóa.");
                    showAlert(@"Lỗi", @"Không tìm thấy class mod nào!");
                }
            }
        }
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
    writeLog([NSString stringWithFormat:@"Toggle ImGui: %d -> %d", current, !current]);
}
@end

// === Các IMP giả ===
static void dummy_imp(id self, SEL _cmd, ...) { writeLog(@"dummy_imp called"); }

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

static id fake_udid_imp(id self, SEL _cmd) { return @"00000000-0000-0000-0000-000000000000"; }
static void dummy_save_udid(id self, SEL _cmd, id udid) {}

// === Swizzles ===
void perform_swizzles(void) {
    writeLog(@"perform_swizzles started");
    // 1. Block network
    Class netTool = objc_getClass("NetTool");
    if (netTool) {
        SEL postSel = NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:");
        Method m = class_getClassMethod(netTool, postSel);
        if (m) { method_setImplementation(m, (IMP)dummy_imp); writeLog(@"✅ NetTool post swizzled"); }
    }

    // 2. Bypass decrypt – gọi bootstrap
    Class fwEnc = objc_getClass("FWEncryptorAES");
    if (fwEnc) {
        SEL decSel = NSSelectorFromString(@"decrypt:Key:IV:");
        Method m = class_getClassMethod(fwEnc, decSel);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^id(id self, NSData *cipher, NSData *key, NSData *iv) {
                writeLog(@"🔥 decrypt called – forcing bootstrap");
                showAlert(@"decrypt", @"Đã chặn decrypt, gọi menu...");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [LQBypassHelper bootstrapModMenu];
                });
                return [NSData data];
            });
            method_setImplementation(m, newImp);
            writeLog(@"✅ FWEncryptorAES decrypt swizzled");
        }
    }

    // 3. Overlay windows
    Class overlayWin = objc_getClass("APIClientOverlayWindow");
    if (overlayWin) {
        Method m1 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"makeKeyAndVisible"));
        if (m1) { method_setImplementation(m1, (IMP)dummy_imp); }
        Method m2 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"initWithFrame:"));
        if (m2) { method_setImplementation(m2, (IMP)dummy_init_hidden); }
        Method m3 = class_getInstanceMethod(overlayWin, NSSelectorFromString(@"updateFrame"));
        if (m3) { method_setImplementation(m3, (IMP)dummy_imp); }
        writeLog(@"✅ OverlayWindow swizzled");
    }

    // 4. ASStatusView
    Class statusView = objc_getClass("ASStatusView");
    if (statusView) {
        NSArray *selectors = @[
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
        for (NSString *selName in selectors) {
            SEL sel = NSSelectorFromString(selName);
            Method m = class_getInstanceMethod(statusView, sel);
            if (m) method_setImplementation(m, (IMP)dummy_imp);
        }
        writeLog(@"✅ ASStatusView swizzled");
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

    // 6. HUDs
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
        writeLog(@"✅ Keychain swizzled");
    }

    writeLog(@"perform_swizzles completed");
}

// === Entry point ===
__attribute__((constructor))
static void lq_bypass_init(void) {
    writeLog(@"LQBypass dylib loaded (constructor)");
    showAlert(@"LQBypass", @"Dylib đã load! Đang chờ...");

    dispatch_async(dispatch_get_main_queue(), ^{
        perform_swizzles();
    });

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        writeLog(@"UIApplicationDidFinishLaunchingNotification received");
        showAlert(@"App Launch", @"Đã nhận notification launch!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassHelper bootstrapModMenu];
            [LQBypassHelper dismissAllOverlays];
        });
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        writeLog(@"Fallback 3s trigger");
        [LQBypassHelper bootstrapModMenu];
        [LQBypassHelper dismissAllOverlays];
    });
}
