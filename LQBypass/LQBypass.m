// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 9.0: UI Spawner (Kết hợp hoàn hảo với Hex Patch)
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface LQBypassUI : NSObject
@end

@implementation LQBypassUI

+ (void)spawnMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin) keyWin = [UIApplication sharedApplication].windows.firstObject;
        if (!keyWin) return;

        NSLog(@"[LQBypass] Bắt đầu gọi UI Menu...");

        // 1. Tạo controller và vẽ nút bấm nổi (Floating Buttons)
        Class ctrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (ctrlCls) {
            id ctrl = [[ctrlCls alloc] init];
            SEL setupSel = NSSelectorFromString(@"setupFloatingToggleButtons");
            if ([ctrl respondsToSelector:setupSel]) {
                ((void (*)(id, SEL))objc_msgSend)(ctrl, setupSel);
                NSLog(@"[LQBypass] ✅ Đã spawn Floating Buttons!");
            }
        }
        
        // 2. Ép cờ ImGuiDrawView hiện lên ngay lập tức
        Class imguiCls = objc_getClass("ImGuiDrawView");
        if (imguiCls) {
            SEL setVis = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
            if ([imguiCls respondsToSelector:setVis]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(imguiCls, setVis, YES);
                NSLog(@"[LQBypass] ✅ Đã bật ImGui Menu Mod!");
            }
        }
    });
}

@end

__attribute__((constructor))
static void init_ui() {
    NSLog(@"[LQBypass] ⚡ Dylib v9.0 UI Spawner đã nạp!");
    
    // Đợi game khởi động xong UIWindow (khoảng 3 giây sau khi launch)
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [LQBypassUI spawnMenu];
        });
    }];
}
