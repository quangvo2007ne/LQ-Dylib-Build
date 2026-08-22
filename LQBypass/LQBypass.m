// =========================================================================
//  LQBypass.m — Tweak Dylib Chủ Quản Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 10.1: Stealth (fishhook) + Direct RAM Bypass
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>
#include "fishhook.h"

// =========================================================
// STEALTH LAYER — Ẩn LQBypass khỏi scan của anogs/ACE
// anogs dùng _dyld_get_image_name x4 và dlopen x23 để điều tra
// =========================================================
static const char *(*orig_dyld_get_image_name)(uint32_t) = NULL;
static const char *hook_dyld_get_image_name(uint32_t idx) {
    const char *name = orig_dyld_get_image_name(idx);
    if (name && strstr(name, "LQBypass")) {
        // Giả vờ đây là một framework hệ thống bình thường
        return "/System/Library/Frameworks/CoreData.framework/CoreData";
    }
    return name;
}

static void install_stealth_hooks(void) {
    struct rebinding hooks[] = {
        {"_dyld_get_image_name", (void *)hook_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
    };
    rebind_symbols(hooks, 1);
}

// =========================================================
// WATCHDOG TERMINATION HOOKS — bẫy exit/abort của AWSS3
// Frida termination observer hook đúng những hàm này → menu hiện
// Ta replicate bằng fishhook để không cần Frida
// =========================================================
static void (*orig_exit)(int) = NULL;
static void (*orig__exit)(int) = NULL;
static void (*orig_abort)(void) = NULL;
static int  (*orig_kill)(pid_t, int) = NULL;

static void hook_exit(int code) {
    // Nuốt lệnh exit từ watchdog — không cho nó tắt process
    NSLog(@"[LQBypass] 🛡 hook_exit(%d) bị chặn!", code);
}
static void hook__exit(int code) {
    NSLog(@"[LQBypass] 🛡 hook__exit(%d) bị chặn!", code);
}
static void hook_abort(void) {
    NSLog(@"[LQBypass] 🛡 hook_abort() bị chặn!");
}
static int hook_kill(pid_t pid, int sig) {
    if (pid == getpid()) {
        // Tự kill chính mình = watchdog cố tắt game
        NSLog(@"[LQBypass] 🛡 hook_kill(self, %d) bị chặn!", sig);
        return 0;
    }
    return orig_kill ? orig_kill(pid, sig) : 0;
}

static void install_termination_hooks(void) {
    struct rebinding hooks[] = {
        {"exit",   (void *)hook_exit,   (void **)&orig_exit},
        {"_exit",  (void *)hook__exit,  (void **)&orig__exit},
        {"abort",  (void *)hook_abort,  (void **)&orig_abort},
        {"kill",   (void *)hook_kill,   (void **)&orig_kill},
    };
    rebind_symbols(hooks, 4);
}


// Forward declaration (định nghĩa đầy đủ ở bên dưới)
static void lq_log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);

// =========================================================
// PATCH RUNTIME — tắt vòng reset visible trong drawInMTKView:
// =========================================================
// drawInMTKView: gọi validator rồi reset visible=0 mỗi frame nếu validator fail:
//   0x02EE83B8  BL   sub_2F545C4
//   0x02EE83BC  TBNZ W0,#0,0x02EE83C8   ; nếu valid→skip
//   0x02EE83C0  ADRP X8, 0x036BD000
//   0x02EE83C4  STRB WZR, [X8,#0x68]   ; visible = 0  ← 600+ lần/phiên!
// Fix: thay TBNZ bằng B unconditional → luôn skip reset
//   0x02EE83BC  B 0x02EE83C8  = 0x14000003
static BOOL patch_draw_reset(uintptr_t slide) {
    uintptr_t patch_va  = slide + 0x02EE83BC;  // địa chỉ runtime
    uint32_t  instr     = 0x14000003;          // B +12 byte (bản le)
    uintptr_t page_addr = patch_va & ~0xFFFUL; // căn chỉnh trang 4 KB

    // Mở quyền ghi
    if (mprotect((void *)page_addr, 0x1000, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        lq_log(@"\u274c patch_draw_reset: mprotect RWX fail (errno=%d)", errno);
        return NO;
    }

    // Ghi 4 byte
    *(uint32_t *)patch_va = instr;
    sys_icache_invalidate((void *)patch_va, 4); // flush instruction cache ARM64

    // Trả về RX
    mprotect((void *)page_addr, 0x1000, PROT_READ | PROT_EXEC);

    lq_log(@"\u2705 patch_draw_reset: đã ghi B @ 0x02EE83BC → visible sẽ không bị reset mỗi frame!");
    return YES;
}

// =========================================================
// ON-SCREEN LOG WINDOW — hiện thị log ngay trên màn hình
// =========================================================
static UIWindow   *s_logWindow  = nil;
static UITextView *s_logView    = nil;
static NSString   *s_logFilePath = nil;

static void lq_log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void lq_log(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[LQBypass] %@\n", msg];

    // Ghi ra file
    if (s_logFilePath) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:s_logFilePath];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    }

    // Ghi ra NSLog (xcode console)
    NSLog(@"%@", line);

    // Hiện lên UITextView trên màn hình (main thread)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_logView) {
            s_logView.text = [s_logView.text stringByAppendingString:line];
            // Auto-scroll xuống cuối
            NSRange range = NSMakeRange(s_logView.text.length, 0);
            [s_logView scrollRangeToVisible:range];
        }
    });
}

@interface LQHelper : NSObject
+ (instancetype)shared;
- (void)didTapHide;
- (void)didTapRetry;
@end

@implementation LQHelper
+ (instancetype)shared {
    static LQHelper *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[LQHelper alloc] init]; });
    return inst;
}
- (void)didTapHide  { s_logWindow.hidden = YES; }
- (void)didTapRetry {
    // Reset và spawn lại — được gọi khi đã vào game
    extern void lq_retry_spawn(void);
    lq_retry_spawn();
}
@end

// =========================================================
// MOCK GESTURE — Dùng để đánh lừa hàm showMenu:
// =========================================================
@interface LQMockGesture : NSObject
@property (nonatomic, assign) NSInteger state;
@end
@implementation LQMockGesture
@end

static void setup_log_window(void) {
    // File log trong Documents
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    s_logFilePath = [docs stringByAppendingPathComponent:@"lqbypass_log.txt"];
    [@"=== LQBypass v9.4 Log Start ===\n" writeToFile:s_logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // UIWindow nhỏ — chỉ chiếm 1/3 trên màn hình, không che gameplay
    CGFloat W = [UIScreen mainScreen].bounds.size.width;
    CGFloat H = 300.0f; // chiều cao cố định
    UIWindowScene *scene = nil;
    for (UIWindowScene *ws in [UIApplication sharedApplication].connectedScenes) {
        if (ws.activationState == UISceneActivationStateForegroundActive) { scene = ws; break; }
    }
    if (@available(iOS 13.0, *)) {
        if (scene) s_logWindow = [[UIWindow alloc] initWithWindowScene:scene];
    }
    if (!s_logWindow) s_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    else s_logWindow.frame = CGRectMake(0, 0, W, H);

    s_logWindow.windowLevel = UIWindowLevelAlert + 100;
    s_logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.70];
    s_logWindow.userInteractionEnabled = YES;

    // Text view log
    s_logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 60, W - 16, 230)];
    s_logView.backgroundColor = [UIColor clearColor];
    s_logView.textColor        = [UIColor greenColor];
    s_logView.font             = [UIFont fontWithName:@"Courier" size:11];
    s_logView.editable         = NO;
    s_logView.text             = @"";
    [s_logWindow addSubview:s_logView];

    // Nút [Ẩn] — dùng LQHelper làm target
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(W - 70, 16, 60, 34);
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
    closeBtn.layer.cornerRadius = 6;
    [closeBtn setTitle:@"[Ẩn]" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor yellowColor] forState:UIControlStateNormal];
    [closeBtn addTarget:[LQHelper shared] action:@selector(didTapHide) forControlEvents:UIControlEventTouchUpInside];
    [s_logWindow addSubview:closeBtn];

    // Nút ▶ Gọi Menu Lại — dùng LQHelper làm target
    UIButton *retryBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    retryBtn.frame = CGRectMake(8, 16, 145, 34);
    retryBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.1 alpha:0.9];
    retryBtn.layer.cornerRadius = 6;
    [retryBtn setTitle:@"▶ Gọi Menu (sau login)" forState:UIControlStateNormal];
    [retryBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [retryBtn addTarget:[LQHelper shared] action:@selector(didTapRetry) forControlEvents:UIControlEventTouchUpInside];
    [s_logWindow addSubview:retryBtn];

    s_logWindow.hidden = NO;
    // KHÔNG gọi makeKeyAndVisible — game window phải giữ keyWindow
    // initTapGes dùng keyWindow để đính floating button
    // log window vẫn hiện do windowLevel cao hơn game
}


// Ẩn log window
__attribute__((visibility("default")))
void lq_hide_log(void) {
    s_logWindow.hidden = YES;
}
// lq_retry_spawn được định nghĩa sau phần SPAWN MENU (tránh forward-decl lỗi)

// =========================================================
// LẤY SLIDE AN TOÀN (không dùng _dyld_get_image_name bị hook)
// =========================================================
static uintptr_t get_awss3_slide_safe(void) {
    // Constructor 7 hook cả _dyld_get_image_name lẫn dladdr để ẩn AWSS3.
    // Không dùng cả hai. Tính slide thuần túy từ IMP:
    //   slide = runtime_IMP - va_unslid
    // VA unslid của initTapGes = 0x02F04DC4 (từ objc_interfaces.h)
    Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
    if (!cls) { lq_log(@"❌ SLIDE: objc_getClass fail"); return 0; }

    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"initTapGes"));
    if (!m) { lq_log(@"❌ SLIDE: getInstanceMethod fail"); return 0; }

    IMP imp = method_getImplementation(m);
    if (!imp) { lq_log(@"❌ SLIDE: getImplementation fail"); return 0; }

    // Tính slide trực tiếp — không cần dladdr
    uintptr_t va_unslid = 0x02F04DC4;
    uintptr_t slide = (uintptr_t)imp - va_unslid;
    lq_log(@"✅ SLIDE OK: imp=%p va=0x%lX slide=0x%lX", (void*)imp, va_unslid, slide);
    return slide;
}

// =========================================================
// SPAWN MENU
// =========================================================
static id   global_ctrl  = nil;
static BOOL menu_spawned = NO;
static uintptr_t g_slide = 0; // Lưu slide cho hook dùng

// ------- Hook showMenu: — bypass gesture.state check -------
static IMP orig_showMenu = NULL;
static void hook_showMenu(id self, SEL _cmd, id gesture) {
    // Không quan tâm gesture.state — đưa thẳng tới bật ImGui
    lq_log(@"👀 showMenu: bị bắt — ép visible...");
    @try {
        // Ưu tiên: gọi class method chính thức
        Class imguiCls = objc_getClass("ImGuiDrawView");
        if (imguiCls) {
            SEL setVis = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
            if ([imguiCls respondsToSelector:setVis]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(imguiCls, setVis, YES);
                lq_log(@"\u2705 FWBwynoreHMvFPjuQkTf:YES — ImGui ON!");
            }
        }
        // Dự phòng: ghi thẳng cờ
        if (g_slide) {
            *(volatile uint8_t *)(g_slide + 0x36BD068) = 1;
            *(volatile uint8_t *)(g_slide + 0x036C2480) = 0; // inverse_visibility
        }
        // Gọi resetIconVisibilityTimer để giữ trạng thái ổn định
        SEL resetSel = NSSelectorFromString(@"resetIconVisibilityTimer");
        if (self && [self respondsToSelector:resetSel]) {
            ((void (*)(id, SEL))objc_msgSend)(self, resetSel);
        }
    } @catch (NSException *e) {
        lq_log(@"\u274c hook_showMenu ex: %@", e.reason);
    }
}

static void install_showmenu_hook(id ctrl) {
    Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"showMenu:");
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        orig_showMenu = method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_showMenu);
        lq_log(@"\u2705 Hook showMenu: đã cài!");
    }
}

static void force_imgui_visible(uintptr_t slide) {
    @try {
        Class imguiCls = objc_getClass("ImGuiDrawView");
        if (imguiCls) {
            SEL setVis = NSSelectorFromString(@"FWBwynoreHMvFPjuQkTf:");
            if ([imguiCls respondsToSelector:setVis]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(imguiCls, setVis, YES);
                lq_log(@"\u2705 force_imgui: class method OK");
            }
        }
        *(volatile uint8_t *)(slide + 0x36BD068) = 1;
        *(volatile uint8_t *)(slide + 0x036C2480) = 0;
        lq_log(@"\u2705 force_imgui: flags OK");
    } @catch (NSException *e) {
        lq_log(@"\u274c force_imgui ex: %@", e.reason);
    }
}

static void spawn_menu(void) {
    if (menu_spawned) return;
    menu_spawned = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        lq_log(@"→ spawn_menu start");

        uintptr_t slide = get_awss3_slide_safe();
        if (!slide) { lq_log(@"❌ slide=0 abort"); return; }
        g_slide = slide; 

        // BƯỚC 1: Ghi thẳng vào RAM để "đánh lừa" Validator (sub_2F545C4)
        // Validator kiểm tra:
        //   [a] tamper_byte @ 0x036C0208 == 0  (không bị phát hiện hack)
        //   [b] hash_a @ 0x036C01F8 == hash_b @ 0x036C0200 (hash khớp)
        // → Không gọi hàm nào (tránh crash do arg nil), chỉ ghi thẳng vào địa chỉ.
        @try {
            *(volatile uint8_t  *)(slide + 0x036C0208) = 0;
            *(volatile uint64_t *)(slide + 0x036C01F8) = 0xDEADBEEFDEADBEEF;
            *(volatile uint64_t *)(slide + 0x036C0200) = 0xDEADBEEFDEADBEEF;
            lq_log(@"\u2705 Bypass Validator — Integrity State OK!");
        } @catch (NSException *e) {
            lq_log(@"\u274c L\u1ed7i ghi RAM: %@", e.reason);
        }

        // BƯỚC 2: Khởi tạo Controller (Test Harness)
        Class ctrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!ctrlCls) { lq_log(@"❌ class not found"); return; }
        lq_log(@"✅ class found: %@", NSStringFromClass(ctrlCls));

        global_ctrl = [[ctrlCls alloc] init];
        lq_log(@"✅ alloc-init done: %@", global_ctrl);

        // BƯỚC 2: Lưu controller vào global 0x036BDFD0 (bằng con trỏ thô để tránh lỗi ARC)
        void **global_ptr = (void **)(slide + 0x036BDFD0);
        *global_ptr = (__bridge_retained void *)global_ctrl; // Retain +1 vào vùng nhớ C
        lq_log(@"✅ Đã lưu controller vào global 0x036BDFD0!");

        // BƯỚC 3: Dựng giao diện Nút nổi
        SEL selInit = NSSelectorFromString(@"initTapGes");
        if ([global_ctrl respondsToSelector:selInit]) {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(global_ctrl, selInit);
                lq_log(@"✅ initTapGes done — nút nổi xuất hiện!");
            }
            @catch (NSException *e) { lq_log(@"❌ initTapGes ex: %@", e.reason); }
        } else {
            lq_log(@"❌ initTapGes không respond");
        }

        // BƯỚC 4: Cài hook showMenu:
        install_showmenu_hook(global_ctrl);

        // BƯỚC 5: Đồng bộ màu nút (luồng chuẩn game gọi)
        SEL selSetup = NSSelectorFromString(@"setupFloatingToggleButtons");
        if ([global_ctrl respondsToSelector:selSetup]) {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(global_ctrl, selSetup);
                lq_log(@"✅ setupFloatingToggleButtons done!");
            }
            @catch (NSException *e) { lq_log(@"❌ setupFloating ex: %@", e.reason); }
        }

        // BƯỚC 6: Patch runtime — ngăn drawInMTKView: reset visible về 0 mỗi frame
        patch_draw_reset(slide);

        // BƯỚC 7: Force ImGui visible sau 2s (sau khi patch đã có hiệu lực)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            force_imgui_visible(slide);
        });
    });
}


// Retry spawn — bấm nút "▶ Gọi Menu Lại" sau khi vào game
// Phải đặt SAU spawn_menu để compiler thấy khai báo
__attribute__((visibility("default")))
void lq_retry_spawn(void) {
    lq_log(@"🔄 Retry bởi user...");
    menu_spawned = NO;
    global_ctrl  = nil;
    spawn_menu();
}

// =========================================================
// HOOK makeKeyAndVisible
// =========================================================
static void (*orig_makeKeyAndVisible)(id, SEL);
static void hook_makeKeyAndVisible(id self, SEL _cmd) {
    if (orig_makeKeyAndVisible) orig_makeKeyAndVisible(self, _cmd);

    // Chỉ setup log window 1 lần sau window đầu tiên makeKey
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            setup_log_window();
            lq_log(@"⚡ Log window ready, sẽ spawn menu sau 2.5s...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                spawn_menu();
            });
        });
    });
}

// =========================================================
// CONSTRUCTOR
// =========================================================
__attribute__((constructor))
static void lq_init(void) {
    // ⚡ STEALTH TRƯỚC TIÊN — chạy đồng bộ ngay khi dylib load
    // Đảm bảo anogs chưa kịp quét thì hook đã được cài
    install_stealth_hooks();

    // 🛡 BẪY WATCHDOG — hook exit/abort/kill trước khi Constructor 6 watchdog timer kịp bắn
    // Đây chính là lý do menu hiện khi chạy Frida termination observer
    install_termination_hooks();

    // Hook UIWindow để đợi UI sẵn sàng
    dispatch_async(dispatch_get_main_queue(), ^{
        Class winCls = objc_getClass("UIWindow");
        if (winCls) {
            Method m = class_getInstanceMethod(winCls, @selector(makeKeyAndVisible));
            if (m) {
                orig_makeKeyAndVisible = (void (*)(id, SEL))method_getImplementation(m);
                method_setImplementation(m, (IMP)hook_makeKeyAndVisible);
            }
        }
    });
}
