// CustomModMenu.m
// Mod Menu UI tự thiết kế chuẩn iOS (Dark Glassmorphism UI) kết nối Offsets Hack 8 Ball Pool

#import "CustomModMenu.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#define OFF_AIM_ANGLE           0x00E6B47E
#define OFF_UPDATE_GUIDELINE    0x00E6B620
#define OFF_SPIN_X              0x00E6B43C
#define OFF_SPIN_Y              0x00E6B44E
#define OFF_GOLDEN_SHOT         0x00E6B5E9

@interface CustomModMenu ()
@property (nonatomic, strong) UIButton *floatingBtn;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) BOOL isExtendedGuidelineEnabled;
@property (nonatomic, assign) BOOL isSuperSpinEnabled;
@property (nonatomic, assign) BOOL isGoldenShotEnabled;
@end

@implementation CustomModMenu

+ (instancetype)sharedInstance {
    static CustomModMenu *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CustomModMenu alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isMenuVisible = NO;
        _isExtendedGuidelineEnabled = NO;
        _isSuperSpinEnabled = NO;
        _isGoldenShotEnabled = NO;
    }
    return self;
}

- (void)showFloatingButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.floatingBtn) return;

        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            NSArray *windows = [UIApplication sharedApplication].windows;
            if (windows.count > 0) keyWindow = windows.firstObject;
        }

        // Nút bấm tròn Floating Icon
        self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingBtn.frame = CGRectMake(20, 100, 50, 50);
        self.floatingBtn.layer.cornerRadius = 25;
        self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.85];
        self.floatingBtn.layer.borderWidth = 2.0;
        self.floatingBtn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor;
        [self.floatingBtn setTitle:@"🎱" forState:UIControlStateNormal];
        self.floatingBtn.titleLabel.font = [UIFont systemFontOfSize:24];

        // Đổ bóng (Shadow)
        self.floatingBtn.layer.shadowColor = [UIColor cyanColor].CGColor;
        self.floatingBtn.layer.shadowOffset = CGSizeMake(0, 0);
        self.floatingBtn.layer.shadowRadius = 8;
        self.floatingBtn.layer.shadowOpacity = 0.8;

        // Thêm PanGesture kéo thả nút trên màn hình
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.floatingBtn addGestureRecognizer:pan];
        [self.floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

        [keyWindow addSubview:self.floatingBtn];
        [self setupMenuViewInWindow:keyWindow];
    });
}

- (void)hideFloatingButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingBtn removeFromSuperview];
        self.floatingBtn = nil;
        [self.menuView removeFromSuperview];
        self.menuView = nil;
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.floatingBtn.superview];
    self.floatingBtn.center = CGPointMake(self.floatingBtn.center.x + translation.x, self.floatingBtn.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self.floatingBtn.superview];
}

- (void)setupMenuViewInWindow:(UIWindow *)window {
    CGFloat width = 280;
    CGFloat height = 320;
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake((window.bounds.size.width - width)/2, (window.bounds.size.height - height)/2, width, height)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.92];
    self.menuView.layer.cornerRadius = 16;
    self.menuView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.8].CGColor;
    self.menuView.layer.borderWidth = 1.5;
    self.menuView.hidden = YES;

    // Header Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, width, 30)];
    titleLabel.text = @"🎱 8 BALL POOL HACK";
    titleLabel.textColor = [UIColor cyanColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:titleLabel];

    // Divider Line
    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(15, 48, width - 30, 1)];
    divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [self.menuView addSubview:divider];

    // Item 1: Extended Guideline
    [self addToggleItemWithTitle:@"Extended Guideline" yPos:65 action:@selector(toggleGuideline:)];

    // Item 2: Super Spin Control
    [self addToggleItemWithTitle:@"Super Spin Control" yPos:120 action:@selector(toggleSpin:)];

    // Item 3: Golden Shot Mode
    [self addToggleItemWithTitle:@"Golden Shot Mode" yPos:175 action:@selector(toggleGoldenShot:)];

    // Footer Info
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 35, width, 25)];
    footerLabel.text = @"Status: Active | Custom Dylib";
    footerLabel.textColor = [UIColor lightGrayColor];
    footerLabel.font = [UIFont systemFontOfSize:11];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:footerLabel];

    [window addSubview:self.menuView];
}

- (void)addToggleItemWithTitle:(NSString *)title yPos:(CGFloat)y action:(SEL)action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 160, 30)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.menuView addSubview:label];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(self.menuView.bounds.size.width - 70, y - 2, 50, 30)];
    sw.onTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.menuView addSubview:sw];
}

- (void)toggleMenu {
    self.isMenuVisible = !self.isMenuVisible;
    self.menuView.hidden = !self.isMenuVisible;

    // Animation nảy UI
    if (self.isMenuVisible) {
        self.menuView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [UIView animateWithDuration:0.25 animations:^{
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Xử lý logic công tắc Bật/Tắt Offset
// ─────────────────────────────────────────────────────────────────────────────
- (void)toggleGuideline:(UISwitch *)sender {
    self.isExtendedGuidelineEnabled = sender.isOn;
    NSLog(@"[HACK] Extended Guideline %s (Offset: 0x%X)", sender.isOn ? "ON" : "OFF", OFF_AIM_ANGLE);
    // Logic gán memory patch hoặc gọi hook qua ASLR slide ở đây
}

- (void)toggleSpin:(UISwitch *)sender {
    self.isSuperSpinEnabled = sender.isOn;
    NSLog(@"[HACK] Super Spin %s (Offset: 0x%X)", sender.isOn ? "ON" : "OFF", OFF_SPIN_X);
}

- (void)toggleGoldenShot:(UISwitch *)sender {
    self.isGoldenShotEnabled = sender.isOn;
    NSLog(@"[HACK] Golden Shot %s (Offset: 0x%X)", sender.isOn ? "ON" : "OFF", OFF_GOLDEN_SHOT);
}

@end
