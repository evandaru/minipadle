#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "Logger.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        [Logger setupLogging];
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *del = [AppDelegate new];
        app.delegate = del;
        [app run];
    }
    return 0;
}
