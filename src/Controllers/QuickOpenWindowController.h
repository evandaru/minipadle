#import <Cocoa/Cocoa.h>

@protocol QuickOpenDelegate <NSObject>
@optional
- (void)quickOpenDidSelectFilePath:(NSString *)filePath;
@end

@interface QuickOpenWindowController
    : NSWindowController <NSSearchFieldDelegate, NSTableViewDataSource,
                          NSTableViewDelegate, NSWindowDelegate>

@property(nonatomic, assign) id<QuickOpenDelegate> delegate;

- (void)presentWithRootPath:(NSString *)rootPath;
- (void)presentWithRootPath:(NSString *)rootPath isDarkMode:(BOOL)isDark;
- (void)preloadRootPath:(NSString *)rootPath;

@end
