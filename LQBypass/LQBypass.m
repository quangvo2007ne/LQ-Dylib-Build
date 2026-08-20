// =========================================================================
//  LQBypass.m — Tweak Dylib Toàn Diện Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 8.0: Thuận Theo Luồng Auth Tự Nhiên & Fix JSON Schema
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

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
    NSTimeInterval currentUnix = [[NSDate date] timeIntervalSince1970];
    NSNumber *unixNum = @((long long)currentUnix);

    if ([urlStr containsString:@"package-v3"]) {
        // Response cho package-v3: status và unix nằm ở ROOT
        NSDictionary *pkgData = @{
            @"packageName": @"com.garena.game.kgvn",
            @"name": @"LienQuanMobile",
            @"ip": @"127.0.0.1"
        };
        fakeResponse = @{
            @"code": @200,
            @"status": @"success", // Không phải account_not_activated
            @"success": @YES,
            @"unix": unixNum,      // <-- Root unix để qua time check
            @"data": pkgData
        };
    } else if ([urlStr containsString:@"credential-v3"] || [urlStr containsString:@"key-v3"]) {
        // Response cho credential/key
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

// Hook trực tiếp khi chạm vào Nút Nổi -> Bật ngay Bảng Menu Mod!
static void hook_show_menu_imp(id self, SEL _cmd, id gesture) {
    NSLog(@"[LQBypass] 🔘 Đã chạm vào Nút Nổi -> Kích hoạt mở Bảng Menu Mod!");
    [LQBypassHelper openModMenu];
}

void perform_swizzles(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Xóa Key Form trực tiếp để thỏa mãn Rule nếu lỡ hiện
        Class statusCls = objc_getClass("ASStatusView");
        if (statusCls) {
            swizzleMethod(statusCls, NSSelectorFromString(@"layoutLoginForm:centerX:centerY:isLandscape:"), (IMP)dummy_imp);
            swizzleMethod(statusCls, NSSelectorFromString(@"layoutExpiredForm:centerX:centerY:isLandscape:"), (IMP)dummy_imp);
        }

        // Hook Keychain UDID
        Class cls = objc_getClass("VKKeychainUDID");
        if (!cls) cls = objc_getClass("VKKeychainIDFV");
        if (cls) {
            swizzleMethod(cls, NSSelectorFromString(@"VKgetUdidFromKeyChain"), (IMP)fake_udid_imp);
            swizzleMethod(cls, NSSelectorFromString(@"VKsaveUdidToKeyChain:"), (IMP)dummy_save_udid);
        }

        // Hook NetTool Fake
        Class netToolCls = objc_getClass("NetTool");
        if (netToolCls) {
            Method m1 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"));
            if (m1) swizzleMethod(netToolCls, NSSelectorFromString(@"Post_AppendURL:myparameters:mysuccess:myfailure:"), method_getImplementation(m1));
            Method m2 = class_getClassMethod([NetToolFake class], NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"));
            if (m2) swizzleMethod(netToolCls, NSSelectorFromString(@"verifySignature:withData:usingPublicKeyString:"), method_getImplementation(m2));
        }

        // Hook showMenu: trên controller nút nổi để gắn tính năng 2-in-1
        Class modCtrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (modCtrlCls) {
            swizzleMethod(modCtrlCls, NSSelectorFromString(@"showMenu:"), (IMP)hook_show_menu_imp);
            NSLog(@"[LQBypass] ✅ Đã gắn hook showMenu: -> openModMenu");
        }

        NSLog(@"[LQBypass] ✅ Swizzles hoàn tất!");
    });
}

// -------------------------------------------------------------------------
// 5. Constructor
// -------------------------------------------------------------------------
__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] ⚡ Dylib v8.0 đã nạp thành công!");

    // KHÔNG TỰ ĐỘNG GỌI bootstrap_mod_menu NỮA!
    // Trả lại luồng tự nhiên cho Game. Game sẽ tự động gọi Completion Block 
    // tại 0x02F085B4 sau khi Fake Network Auth thành công, 
    // và Block đó sẽ tự động cấu hình integrity + Menu Mod chuẩn xác 100%!

    perform_swizzles();

    // Vẫn thêm cử chỉ chạm 2 ngón 2 lần để backup bật Bảng Menu Mod
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
