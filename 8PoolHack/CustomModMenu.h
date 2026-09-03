// CustomModMenu.h
// UI Mod Menu phong cách hiện đại (Dark Glassmorphism UI) cho 8 Ball Pool iOS

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CustomModMenu : NSObject

+ (instancetype)sharedInstance;
- (void)showFloatingButton;
- (void)hideFloatingButton;

@end
