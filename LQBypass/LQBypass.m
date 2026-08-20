// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 9.2: Gọi đúng initTapGes + pre-conditions từ deep_flow_v2
//
//  Root cause phân tích:
//  - setupFloatingToggleButtons chỉ sync màu nút, KHÔNG tạo nút/overlay
//  - Phải gọi initTapGes (0x02F04DC4) sau khi seed + one-time-init đã sẵn sàng
//  - one-time-init (sub_2F54644 @ 0x02F54644) được gọi ngay trong block 0x02F085B4
//  - Nên ta phải gọi sub_2F54644 trước rồi mới initTapGes
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>

static id global_menu_ctrl = nil;
static BOOL menu_spawned = NO;

uintptr_t get_awss3_slide(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "AWSS3.framework/AWSS3"))
            return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
    }
    return 0;
}

static void spawn_menu(void) {
    if (menu_spawned) return;
    menu_spawned = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        uintptr_t slide = get_awss3_slide();
        if (!slide) {
            NSLog(@"[LQBypass] ❌ Không tìm được AWSS3 slide!");
            return;
        }
        NSLog(@"[LQBypass] slide = 0x%lX", slide);

        // Bước 1: Set seed (API-client token) — cần thiết cho integrity state
        NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
        void (*set_token)(id) = (void (*)(id))(slide + 0x00CB80A0);
        set_token(seed);
        NSLog(@"[LQBypass] ✅ Bước 1: set_token done");

        // Bước 2: Chạy one-time initialization (sub_2F54644)
        // Đây là hàm one-time init được gọi trong block 0x02F085B4 trước initTapGes
        void (*one_time_init)(void) = (void (*)(void))(slide + 0x02F54644);
        one_time_init();
        NSLog(@"[LQBypass] ✅ Bước 2: one_time_init done");

        // Bước 3: Tạo controller và gọi initTapGes (tạo toàn bộ overlay + ImGui + nút bấm)
        Class ctrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!ctrlCls) {
            NSLog(@"[LQBypass] ❌ Không tìm được class tXGBBDJNKKzPYcSGmlav!");
            return;
        }

        global_menu_ctrl = [[ctrlCls alloc] init];
        SEL initTapGes = NSSelectorFromString(@"initTapGes");
        if ([global_menu_ctrl respondsToSelector:initTapGes]) {
            ((void (*)(id, SEL))objc_msgSend)(global_menu_ctrl, initTapGes);
            NSLog(@"[LQBypass] ✅ Bước 3: initTapGes done — Menu đang khởi tạo!");
        } else {
            NSLog(@"[LQBypass] ❌ Không tìm thấy initTapGes!");
        }
    });
}

// Hook -[UIWindow makeKeyAndVisible] để chắc chắn UIWindow đã sẵn sàng
static void (*orig_makeKeyAndVisible)(id, SEL);
static void hook_makeKeyAndVisible(id self, SEL _cmd) {
    if (orig_makeKeyAndVisible) orig_makeKeyAndVisible(self, _cmd);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        spawn_menu();
    });
}

__attribute__((constructor))
static void lq_init(void) {
    NSLog(@"[LQBypass] ⚡ Dylib v9.2 đã nạp!");

    Class winCls = objc_getClass("UIWindow");
    if (winCls) {
        Method m = class_getInstanceMethod(winCls, @selector(makeKeyAndVisible));
        if (m) {
            orig_makeKeyAndVisible = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_makeKeyAndVisible);
        }
    }
}
