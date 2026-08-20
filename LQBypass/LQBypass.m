#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// =========================================================================
//  LQBypass.m — Tweak Dylib Hook cho Liên Quân Mobile iOS Mod (AWSS3)
//  Tác giả: Reverse Engineering Assistant
// =========================================================================

static id g_modControllerInstance = nil;

// -------------------------------------------------------------------------
// 1. Khai báo Class Helper trước để tránh lỗi undeclared identifier
// -------------------------------------------------------------------------
@interface LQBypassHelper : NSObject
+ (void)toggleImGuiMenu;
+ (void)bootstrapModMenu;
@end

@implementation LQBypassHelper

+ (void)toggleImGuiMenu {
    Class imguiCls = objc_getClass("ImGuiDrawView");
    if (imguiCls) {
        SEL getVisSel = NSSelectorFromString(@"GmmtbwBOlBYaQRpBHDVm");
        SEL setVisSel = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
        if ([imguiCls respondsToSelector:getVisSel] && [imguiCls respondsToSelector:setVisSel]) {
            BOOL (*getVis)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
            void (*setVis)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
            
            BOOL current = getVis(imguiCls, getVisSel);
            setVis(imguiCls, setVisSel, !current);
            NSLog(@"[LQBypass] Toggle ImGui Menu: %d -> %d", current, !current);
        }
    }
}

+ (void)bootstrapModMenu {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LQBypass] Bắt đầu khởi tạo Menu Mod...");
        
        Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (cls) {
            g_modControllerInstance = [[cls alloc] init];
            NSLog(@"[LQBypass] Đã tạo instance tXGBBDJNKKzPYcSGmlav: %@", g_modControllerInstance);
            
            // Tìm image slide của AWSS3
            uintptr_t slide = 0;
            uint32_t count = _dyld_image_count();
            for (uint32_t i = 0; i < count; i++) {
                const char *name = _dyld_get_image_name(i);
                if (name && strstr(name, "AWSS3.framework/AWSS3")) {
                    slide = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
                    break;
                }
            }
            
            if (slide > 0) {
                uintptr_t *cache_ptr = (uintptr_t *)(slide + 0x36BDFD0);
                *cache_ptr = (uintptr_t)g_modControllerInstance;
                NSLog(@"[LQBypass] Đã ghi instance vào BSS cache @ %p", cache_ptr);
            }
            
            // Kích hoạt tạo cử chỉ và vẽ nút tròn nổi
            if ([g_modControllerInstance respondsToSelector:@selector(initTapGes)]) {
                [g_modControllerInstance performSelector:@selector(initTapGes)];
                NSLog(@"[LQBypass] Đã gọi [initTapGes] thành công!");
            } else if ([g_modControllerInstance respondsToSelector:@selector(setupFloatingToggleButtons)]) {
                [g_modControllerInstance performSelector:@selector(setupFloatingToggleButtons)];
                NSLog(@"[LQBypass] Đã gọi [setupFloatingToggleButtons] thành công!");
            }
        } else {
            NSLog(@"[LQBypass] CẢNH BÁO: Không tìm thấy class tXGBBDJNKKzPYcSGmlav");
        }
        
        // Thêm cử chỉ dự phòng: Gõ 2 ngón 2 lần (2-finger double tap) để ép bật/tắt Menu ImGui
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *w in scene.windows) {
                            if (w.isKeyWindow) { window = w; break; }
                        }
                    }
                    if (window) break;
                }
            }
            if (!window && [[UIApplication sharedApplication].windows count] > 0) {
                window = [UIApplication sharedApplication].windows.firstObject;
            }
            if (window) {
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[LQBypassHelper class] action:@selector(toggleImGuiMenu)];
                tap.numberOfTouchesRequired = 2;
                tap.numberOfTapsRequired = 2;
                [window addGestureRecognizer:tap];
                NSLog(@"[LQBypass] Đã thêm cử chỉ dự phòng (chạm 2 lần bằng 2 ngón) vào UIWindow!");
            }
        });
    });
}

@end

// -------------------------------------------------------------------------
// 2. Hook vô hiệu hoá Dialog Key & UDID (ASStatusView)
// -------------------------------------------------------------------------
static void hook_status_view(void) {
    Class statusViewCls = objc_getClass("ASStatusView");
    if (!statusViewCls) return;
    
    id dummyBlock = ^(id self, ...) {
        NSLog(@"[LQBypass] Chặn thành công Popup Key / UDID!");
    };
    IMP dummyImp = imp_implementationWithBlock(dummyBlock);
    
    const char *selectors_to_mute[] = {
        "showLoginForm",
        "showLoginFormWithTitle:description:placeholder:submitTitle:contactTitle:countdownFrom:",
        "showExpiredForm",
        "showExpiredWithTitle:message:changeKeyTitle:copyUDIDTitle:copyKeyTitle:countdownFrom:",
        "showLoginError:",
        "showLoginLoading",
        "showUDIDAlertWithTitle:message:leftTitle:rightTitle:leftAction:rightAction:",
        "layoutLoginForm:centerX:centerY:isLandscape:",
        "layoutExpiredForm:centerX:centerY:isLandscape:"
    };
    
    for (int i = 0; i < sizeof(selectors_to_mute)/sizeof(selectors_to_mute[0]); i++) {
        SEL sel = sel_registerName(selectors_to_mute[i]);
        Method m = class_getInstanceMethod(statusViewCls, sel);
        if (m) {
            method_setImplementation(m, dummyImp);
        }
    }
}

// -------------------------------------------------------------------------
// 3. Entry point khi Dylib được nạp vào App
// -------------------------------------------------------------------------
__attribute__((constructor))
static void lq_bypass_init(void) {
    NSLog(@"[LQBypass] Tweak dylib đã được nạp thành công vào tiến trình!");
    
    // 1. Hook chặn dialog key ngay lập tức
    dispatch_async(dispatch_get_main_queue(), ^{
        hook_status_view();
    });
    
    // 2. Lắng nghe sự kiện App đã khởi động xong UI -> Khởi tạo Menu Mod
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[LQBypass] Nhận thông báo UIApplicationDidFinishLaunchingNotification!");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [LQBypassHelper bootstrapModMenu];
        });
    }];
    
    // 3. Dự phòng nếu notification đã trôi qua
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [LQBypassHelper bootstrapModMenu];
    });
}
