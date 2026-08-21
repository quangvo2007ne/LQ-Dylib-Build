// DumpHook_Safe.m
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

__attribute__((constructor))
static void init() {
    NSLog(@"[LQBypass] 🚀 DumpHook Safe Edition đang nạp...");

    Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"initTapGes"));
    if (!m) return;
    uintptr_t slide = (uintptr_t)method_getImplementation(m) - 0x02F04DC4;
    NSLog(@"[LQBypass] ✅ Slide = 0x%lX", slide);

    // Tăng delay lên 15 giây để user KỊP ĐĂNG NHẬP vào tận sảnh Lobby
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        NSLog(@"[LQBypass] ⏳ Bắt đầu gọi Menu (chờ user vào Lobby)...");
        
        NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
        void (*set_token)(id) = (void (*)(id))(slide + 0x00CB80A0);
        if (set_token) set_token(seed);

        id (*get_key)(void) = (id (*)(void))(slide + 0x00D2860C);
        id (*get_state)(void) = (id (*)(void))(slide + 0x00D94DB8);
        void (*set_integrity)(id, id, id) = (void (*)(id, id, id))(slide + 0x02F544A0);
        
        id key = get_key ? get_key() : nil;
        id state = get_state ? get_state() : nil;
        
        // Bắt buộc phải có key/state mới gọi set_integrity
        if (key && state && set_integrity) {
            set_integrity(seed, key, state);
            NSLog(@"[LQBypass] ✅ Đã set integrity state!");
        } else {
            NSLog(@"[LQBypass] ❌ Thất bại: Chưa lấy được key/state (Bác chưa đăng nhập xong?)");
            return;
        }

        void (*one_time_init)(void) = (void (*)(void))(slide + 0x02F54644);
        if (one_time_init) one_time_init();

        // Không đọc pointer từ BSS số lẻ, cứ tạo mới cho an toàn
        id global_ctrl = [[cls alloc] init];
        SEL sel = NSSelectorFromString(@"initTapGes");
        if ([global_ctrl respondsToSelector:sel]) {
            ((void (*)(id, SEL))objc_msgSend)(global_ctrl, sel);
            NSLog(@"[LQBypass] ✅ Đã gọi initTapGes thành công!");
        }
        
        // Ghi thẳng BSS để mở ImGui
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            uint8_t *g_menu_flag = (uint8_t *)(slide + 0x36BD068);
            *g_menu_flag = 1; 
            NSLog(@"[LQBypass] 🔥 Đã ép menu ImGui bung lên!");
        });
    });
}
