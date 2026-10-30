#import <Cocoa/Cocoa.h>

extern NSString *const MiniPadleSettingsChangedNotification;

@interface SettingsWindowController : NSWindowController

+ (instancetype)sharedController;

@end
