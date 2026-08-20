// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 9.1: Bulletproof UI Spawner (Sửa lỗi mất Menu ESP)
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id global_menu_ctrl = nil;
static BOOL menu_spawned = NO;

static void spawn_menu_if_needed(void) {
    if (menu_spawned) return;
    menu_spawned = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[LQBypass] Bắt đầu gọi UI Menu từ makeKeyAndVisible...");

        // 1. Giữ reference controller để không bị ARC dọn dẹp (Lỗi dealloc)
        Class ctrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (ctrlCls) {
            global_menu_ctrl = [[ctrlCls alloc] init];
            SEL setupSel = NSSelectorFromString(@"setupFloatingToggleButtons");
            if ([global_menu_ctrl respondsToSelector:setupSel]) {
                ((void (*)(id, SEL))objc_msgSend)(global_menu_ctrl, setupSel);
                NSLog(@"[LQBypass] ✅ Đã spawn Floating Buttons an toàn!");
            }
        }
        
        // 2. Ép cờ ImGuiDrawView hiện lên luôn sau 1 giây
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class imguiCls = objc_getClass("ImGuiDrawView");
            if (imguiCls) {
                SEL setVis = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
                if ([imguiCls respondsToSelector:setVis]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(imguiCls, setVis, YES);
                    NSLog(@"[LQBypass] ✅ Đã bật ImGui Menu Mod!");
                }
            }
        });
    });
}

// Hook makeKeyAndVisible để đảm bảo UIWindow đã load xong 100%
static void (*orig_makeKeyAndVisible)(id, SEL);
static void hook_makeKeyAndVisible(id self, SEL _cmd) {
    if (orig_makeKeyAndVisible) {
        orig_makeKeyAndVisible(self, _cmd);
    }
    spawn_menu_if_needed();
}

__attribute__((constructor))
static void init_ui() {
    NSLog(@"[LQBypass] ⚡ Dylib v9.1 UI Spawner đã nạp!");
    
    Class winCls = objc_getClass("UIWindow");
    if (winCls) {
        Method m = class_getInstanceMethod(winCls, @selector(makeKeyAndVisible));
        if (m) {
            orig_makeKeyAndVisible = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_makeKeyAndVisible);
        }
    }
}
