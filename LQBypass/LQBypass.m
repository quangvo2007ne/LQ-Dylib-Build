// =========================================================================
//  LQBypass.m — Tweak Dylib Cho Liên Quân Mobile (AWSS3.framework)
//  Phiên bản 9.4: On-Screen Log + File Log (debug không cần jailbreak)
// =========================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

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

static void spawn_menu(void) {
    if (menu_spawned) return;
    menu_spawned = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        lq_log(@"→ spawn_menu start");

        uintptr_t slide = get_awss3_slide_safe();
        if (!slide) { lq_log(@"❌ slide=0 abort"); return; }

        // BƯỚC 1: Khởi tạo Controller (Test Harness)
        // Bỏ qua toàn bộ Network, Auth, sub_2F544A0 và sub_2F54644 (watchdog) vì chúng gây crash!
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

        // BƯỚC 4: Đồng bộ màu nút (luồng chuẩn game gọi)
        SEL selSetup = NSSelectorFromString(@"setupFloatingToggleButtons");
        if ([global_ctrl respondsToSelector:selSetup]) {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(global_ctrl, selSetup);
                lq_log(@"✅ setupFloatingToggleButtons done!");
            }
            @catch (NSException *e) { lq_log(@"❌ setupFloating ex: %@", e.reason); }
        }

        // BƯỚC 5: Force ImGui visible bằng cách gọi thẳng showMenu: với Cử chỉ giả
        // Thay vì ghi RAM trực tiếp làm lệch state inverse_visibility (0x036C2480),
        // Ta gọi showMenu: để game tự render full luồng an toàn.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                LQMockGesture *mock = [[LQMockGesture alloc] init];
                mock.state = 3; // UIGestureRecognizerStateEnded = 3
                
                SEL showSel = NSSelectorFromString(@"showMenu:");
                if ([global_ctrl respondsToSelector:showSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(global_ctrl, showSel, mock);
                    lq_log(@"✅ Đã ép bung Menu bằng MockGesture thành công!");
                } else {
                    lq_log(@"❌ Không tìm thấy showMenu:");
                }
            } @catch (NSException *e) {
                lq_log(@"❌ Lỗi gọi showMenu: %@", e.reason);
            }
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
