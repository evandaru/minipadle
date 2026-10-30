#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif

void MPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#ifdef __cplusplus
}
#endif

@interface Logger : NSObject

+ (void)setupLogging;
+ (NSString *)logFilePath;
+ (void)openLogFile;

@end
