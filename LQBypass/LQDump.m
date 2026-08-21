// LQDump.m
// Dylib tự động Dump Data không cần Frida (Method Swizzling)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ==========================================
// HỆ THỐNG GHI LOG RA FILE (Dành cho người dùng Windows)
// ==========================================
static void dump_log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void dump_log(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // 1. In ra Console (xem qua 3uTools hoặc Sideloadly)
    NSLog(@"%@", msg);

    // 2. Ghi ra file lqdump_log.txt trong Documents (Lấy qua 3uTools -> Files)
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *logPath = [docs stringByAppendingPathComponent:@"lqdump_log.txt"];
    NSString *line = [msg stringByAppendingString:@"\n"];
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// ==========================================
// 1. DUMP AES CRYPTO (Bắt gói tin Network)
// ==========================================
@implementation NSString (LQDump)
- (NSString *)lq_AES256EncryptWithKey:(NSString *)key {
    dump_log(@"[LQDump] 📤 ĐANG GỬI DATA LÊN SERVER (Trước mã hóa):\n%@", self);
    return [self lq_AES256EncryptWithKey:key];
}

- (NSString *)lq_AES256DecryptWithKey:(NSString *)key {
    NSString *decrypted = [self lq_AES256DecryptWithKey:key];
    dump_log(@"[LQDump] 📥 DATA TRẢ VỀ TỪ SERVER (Sau giải mã):\n%@", decrypted);
    return decrypted;
}
@end

// ==========================================
// 2. DUMP THÔNG BÁO TỪ SERVER (ASStatusView)
// ==========================================
@interface LQDumpHelper : NSObject @end
@implementation LQDumpHelper
- (void)lq_showErrorWithTitle:(NSString *)title message:(NSString *)msg buttonTitle:(NSString *)btn {
    dump_log(@"[LQDump] ❌ THÔNG BÁO LỖI: [%@] %@", title, msg);
    [self lq_showErrorWithTitle:title message:msg buttonTitle:btn];
}

- (void)lq_showSuccessWithTitle:(NSString *)title message:(NSString *)msg {
    dump_log(@"[LQDump] ✅ THÀNH CÔNG: [%@] %@", title, msg);
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
