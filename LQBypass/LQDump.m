// LQDump.m
// Dylib tự động Dump Data không cần Frida (Method Swizzling)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ==========================================
// 1. DUMP AES CRYPTO (Bắt gói tin Network)
// ==========================================
@implementation NSString (LQDump)
- (NSString *)lq_AES256EncryptWithKey:(NSString *)key {
    NSLog(@"[LQDump] 📤 ĐANG GỬI DATA LÊN SERVER (Trước mã hóa):\n%@", self);
    // Gọi lại hàm gốc (do đã tráo ruột)
    return [self lq_AES256EncryptWithKey:key];
}

- (NSString *)lq_AES256DecryptWithKey:(NSString *)key {
    NSString *decrypted = [self lq_AES256DecryptWithKey:key];
    NSLog(@"[LQDump] 📥 DATA TRẢ VỀ TỪ SERVER (Sau giải mã):\n%@", decrypted);
    return decrypted;
}
@end

// ==========================================
// 2. DUMP THÔNG BÁO TỪ SERVER (ASStatusView)
// ==========================================
@interface LQDumpHelper : NSObject @end
@implementation LQDumpHelper
- (void)lq_showErrorWithTitle:(NSString *)title message:(NSString *)msg buttonTitle:(NSString *)btn {
    NSLog(@"[LQDump] ❌ THÔNG BÁO LỖI: [%@] %@", title, msg);
    // Gọi lại hàm gốc
    [self lq_showErrorWithTitle:title message:msg buttonTitle:btn];
}

- (void)lq_showSuccessWithTitle:(NSString *)title message:(NSString *)msg {
    NSLog(@"[LQDump] ✅ THÀNH CÔNG: [%@] %@", title, msg);
    [self lq_showSuccessWithTitle:title message:msg];
}
@end

// ==========================================
// HÀM ĐỔI RUỘT (SWIZZLING)
// ==========================================
static void hook_class_method(Class targetCls, SEL targetSel, Class myCls, SEL mySel) {
    if (!targetCls) return;
    Method origMethod = class_getInstanceMethod(targetCls, targetSel);
    Method newMethod  = class_getInstanceMethod(myCls, mySel);
    if (origMethod && newMethod) {
        // Tráo đổi ruột 2 hàm cho nhau
        method_exchangeImplementations(origMethod, newMethod);
        NSLog(@"[LQDump] 🪝 Đã hook thành công: %@", NSStringFromSelector(targetSel));
    } else {
        NSLog(@"[LQDump] ⚠️ Thất bại khi hook: %@", NSStringFromSelector(targetSel));
    }
}

__attribute__((constructor))
static void lq_dump_init() {
    NSLog(@"[LQDump] 🚀 Đang khởi động LQDump (Native Hook không dùng Frida)...");

    // 1. Hook Crypto (Mạng)
    Class strCls = objc_getClass("NSString");
    hook_class_method(strCls, NSSelectorFromString(@"AES256EncryptWithKey:"), strCls, @selector(lq_AES256EncryptWithKey:));
    hook_class_method(strCls, NSSelectorFromString(@"AES256DecryptWithKey:"), strCls, @selector(lq_AES256DecryptWithKey:));

    // 2. Hook ASStatusView (Thông báo UI)
    // Đợi 2s để đảm bảo class ASStatusView đã được load
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class asCls = objc_getClass("ASStatusView");
        if (asCls) {
            hook_class_method(asCls, NSSelectorFromString(@"showErrorWithTitle:message:buttonTitle:"), 
                              objc_getClass("LQDumpHelper"), @selector(lq_showErrorWithTitle:message:buttonTitle:));
            
            hook_class_method(asCls, NSSelectorFromString(@"showSuccessWithTitle:message:"), 
                              objc_getClass("LQDumpHelper"), @selector(lq_showSuccessWithTitle:message:));
        } else {
            NSLog(@"[LQDump] ⚠️ Không tìm thấy class ASStatusView");
        }
    });
}
