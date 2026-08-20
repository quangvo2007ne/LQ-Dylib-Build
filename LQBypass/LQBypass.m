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

static void setup_log_window(void) {
    // File log trong Documents
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    s_logFilePath = [docs stringByAppendingPathComponent:@"lqbypass_log.txt"];
    [@"=== LQBypass v9.4 Log Start ===\n" writeToFile:s_logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // UIWindow overlay
    UIWindowScene *scene = nil;
    for (UIWindowScene *ws in [UIApplication sharedApplication].connectedScenes) {
        if (ws.activationState == UISceneActivationStateForegroundActive) {
            scene = ws;
            break;
        }
    }

    if (@available(iOS 13.0, *)) {
        if (scene) s_logWindow = [[UIWindow alloc] initWithWindowScene:scene];
    }
    if (!s_logWindow) s_logWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    s_logWindow.windowLevel = UIWindowLevelAlert + 100;
    s_logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    s_logWindow.userInteractionEnabled = YES;

    // Semi-transparent text view
    CGRect frame = CGRectMake(10, 60, [UIScreen mainScreen].bounds.size.width - 20, 260);
    s_logView = [[UITextView alloc] initWithFrame:frame];
    s_logView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
    s_logView.textColor        = [UIColor greenColor];
    s_logView.font             = [UIFont fontWithName:@"Courier" size:11];
    s_logView.editable         = NO;
    s_logView.text             = @"";
    [s_logWindow addSubview:s_logView];

    // Nút tắt log overlay
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 30, 60, 28);
    [closeBtn setTitle:@"[Ẩn]" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor yellowColor] forState:UIControlStateNormal];
    [closeBtn addTarget:nil action:@selector(lq_hide_log) forControlEvents:UIControlEventTouchUpInside];
    [s_logWindow addSubview:closeBtn];

    s_logWindow.hidden = NO;
    [s_logWindow makeKeyAndVisible];
}

// Ẩn log window
__attribute__((visibility("default")))
void lq_hide_log(void) {
    s_logWindow.hidden = YES;
}

// =========================================================
// LẤY SLIDE AN TOÀN (không dùng _dyld_get_image_name bị hook)
// =========================================================
static uintptr_t get_awss3_slide_safe(void) {
    Class cls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
    if (!cls) { lq_log(@"❌ SLIDE: objc_getClass fail"); return 0; }

    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"initTapGes"));
    if (!m) { lq_log(@"❌ SLIDE: getInstanceMethod fail"); return 0; }

    IMP imp = method_getImplementation(m);
    if (!imp) { lq_log(@"❌ SLIDE: getImplementation fail"); return 0; }

    Dl_info info;
    if (dladdr((void *)imp, &info) == 0 || !info.dli_fbase) {
        lq_log(@"❌ SLIDE: dladdr fail");
        return 0;
    }

    // VA unslid của initTapGes = 0x02F04DC4 (từ objc_interfaces.h)
    uintptr_t slide = (uintptr_t)imp - 0x02F04DC4;
    lq_log(@"✅ SLIDE OK: imp=%p fbase=%p slide=0x%lX", (void*)imp, info.dli_fbase, slide);
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

        // Bước 1: set seed
        NSString *seed = @"DKehoXVTzOryt1T8/K5V838ftfFHNho8CuP41+HTiNCNi0nwolEDstMEOrlEsxHyiUUj4M/7hRwYD6VApIf9c3kkgQYy6dWE/B69+eT5F0g=";
        void (*set_token)(id) = (void (*)(id))(slide + 0x00CB80A0);
        @try { set_token(seed); lq_log(@"✅ set_token done"); }
        @catch (NSException *e) { lq_log(@"❌ set_token ex: %@", e.reason); }

        // Bước 2: one-time init
        void (*one_time_init)(void) = (void (*)(void))(slide + 0x02F54644);
        @try { one_time_init(); lq_log(@"✅ sub_2F54644 done"); }
        @catch (NSException *e) { lq_log(@"❌ sub_2F54644 ex: %@", e.reason); }

        // Bước 3: initTapGes
        Class ctrlCls = objc_getClass("tXGBBDJNKKzPYcSGmlav");
        if (!ctrlCls) { lq_log(@"❌ class not found"); return; }
        lq_log(@"✅ class found: %@", NSStringFromClass(ctrlCls));

        global_ctrl = [[ctrlCls alloc] init];
        lq_log(@"✅ alloc-init done: %@", global_ctrl);

        SEL sel = NSSelectorFromString(@"initTapGes");
        if ([global_ctrl respondsToSelector:sel]) {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(global_ctrl, sel);
                lq_log(@"✅ initTapGes done — nút nổi sẽ xuất hiện!");
            }
            @catch (NSException *e) { lq_log(@"❌ initTapGes ex: %@", e.reason); }
        } else {
            lq_log(@"❌ initTapGes không respond");
        }
    });
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
