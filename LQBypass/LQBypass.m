// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 9.3: Fix bug critical - _dyld_get_image_name bị AWSS3 hook ẩn
//
//  PHÂN TÍCH ROOT CAUSE (đọc đủ v2+v3+v4):
//  1. _dyld_get_image_name bị Constructor 7 (0x02F53F20) hook, ẩn "AWSS3"
//     → strstr(name, "AWSS3") KHÔNG BAO GIỜ match → slide luôn = 0
//  2. Không gọi initTapGes trực tiếp vì thiếu sub_2F54644 one-time init
//  3. Giải pháp: dùng dladdr() trên IMP của class AWSS3 đã biết để lấy base
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static id global_menu_ctrl = nil;
static BOOL menu_spawned = NO;

// Lấy slide của AWSS3 an toàn: không dùng _dyld_get_image_name (bị hook ẩn)
// Dùng dladdr() trên IMP của method thuộc AWSS3 class
static uintptr_t get_awss3_slide_safe(void) {
    // tXGBBDJNKKzPYcSGmlav là class nội bộ AWSS3 → IMP nằm trong image AWSS3
    Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
    if (!cls) return 0;
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"initTapGes"));
    if (!m) return 0;
    IMP imp = method_getImplementation(m);
    if (!imp) return 0;

    Dl_info info;
    if (dladdr((void *)imp, &info) == 0 || !info.dli_fbase) return 0;

    // VA unslid của initTapGes = 0x02F04DC4 (từ objc_interfaces.h)
    uintptr_t va_initTapGes = 0x02F04DC4;
    uintptr_t slide = (uintptr_t)imp - va_initTapGes;
    NSLog(@"[LQBypass] dli_fbase = %p, imp = %p, slide = 0x%lX", info.dli_fbase, (void*)imp, slide);
    return slide;
}

static void spawn_menu(void) {
    if (menu_spawned) return;
    menu_spawned = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[LQBypass] Bắt đầu spawn menu...");

        uintptr_t slide = get_awss3_slide_safe();
        if (!slide) {
            NSLog(@"[LQBypass] ❌ Không lấy được slide! Class chưa load?");
            return;
        }

        // Bước 1: Set seed (API-client token) — từ deep_flow_v2 Section 4.2
        NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
        void (*set_token)(id) = (void (*)(id))(slide + 0x00CB80A0);
        set_token(seed);
        NSLog(@"[LQBypass] ✅ Bước 1: _apiclient_set_token done");

        // Bước 2: sub_2F54644 — one-time initialization (gọi trước initTapGes)
        // Từ deep_flow_v2 Section 5.3: block 0x02F085B4 gọi sub_2F54644 trước khi initTapGes
        void (*one_time_init)(void) = (void (*)(void))(slide + 0x02F54644);
        one_time_init();
        NSLog(@"[LQBypass] ✅ Bước 2: sub_2F54644 one-time-init done");

        // Bước 3: Tạo controller + gọi initTapGes (tạo toàn bộ ImGui + overlay + nút)
        // Từ deep_flow_v2 Section 6: initTapGes tạo ImGuiDrawView, floating button, gesture
        // Từ Section 7.3: bản đã patch dùng lifecycle didAddSubview để gọi initTapGes
        Class ctrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!ctrlCls) {
            NSLog(@"[LQBypass] ❌ Không tìm được class!");
            return;
        }
        global_menu_ctrl = [[ctrlCls alloc] init];
        SEL tapGesSel = NSSelectorFromString(@"initTapGes");
        if ([global_menu_ctrl respondsToSelector:tapGesSel]) {
            ((void (*)(id, SEL))objc_msgSend)(global_menu_ctrl, tapGesSel);
            NSLog(@"[LQBypass] ✅ Bước 3: initTapGes đã gọi — nút bấm nổi sẽ xuất hiện!");
        } else {
            NSLog(@"[LQBypass] ❌ initTapGes không tìm thấy trên controller!");
        }
    });
}

// Hook makeKeyAndVisible để chắc UIWindow, UIScene đã sẵn sàng
static void (*orig_makeKeyAndVisible)(id, SEL);
static void hook_makeKeyAndVisible(id self, SEL _cmd) {
    if (orig_makeKeyAndVisible) orig_makeKeyAndVisible(self, _cmd);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        spawn_menu();
    });
}

__attribute__((constructor))
static void lq_init(void) {
    NSLog(@"[LQBypass] ⚡ Dylib v9.3 đã nạp!");

    // Hook UIWindow makeKeyAndVisible — thời điểm UIWindow chắc chắn sẵn sàng
    dispatch_async(dispatch_get_main_queue(), ^{
        Class winCls = objc_getClass("UIWindow");
        if (winCls) {
            Method m = class_getInstanceMethod(winCls, @selector(makeKeyAndVisible));
            if (m) {
                orig_makeKeyAndVisible = (void (*)(id, SEL))method_getImplementation(m);
                method_setImplementation(m, (IMP)hook_makeKeyAndVisible);
                NSLog(@"[LQBypass] ✅ Hook makeKeyAndVisible đã cài!");
            }
        }
    });
}
