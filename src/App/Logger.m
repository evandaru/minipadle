#import "Logger.h"
#import <execinfo.h>
#import <fcntl.h>
#import <signal.h>
#import <sys/stat.h>
#import <unistd.h>

static int gLogFd = -1;
static NSString *gLogFilePath = nil;

static void MPSignalHandler(int sig) {
    const char *sigName = "UNKNOWN";
    switch (sig) {
        case SIGSEGV: sigName = "SIGSEGV (Segmentation fault / Invalid memory access)"; break;
        case SIGBUS:  sigName = "SIGBUS (Bus error / Bad memory alignment)"; break;
        case SIGABRT: sigName = "SIGABRT (Abort signal)"; break;
        case SIGILL:  sigName = "SIGILL (Illegal instruction)"; break;
        case SIGFPE:  sigName = "SIGFPE (Floating point exception)"; break;
        default: break;
    }

    char header[256];
    time_t now = time(NULL);
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    char timeStr[64];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", &tm_info);

    snprintf(header, sizeof(header), "\n[%s] [CRASH] Fatal signal %d (%s) caught!\n--- Stack Trace ---\n",
             timeStr, sig, sigName);

    write(STDERR_FILENO, header, strlen(header));
    if (gLogFd >= 0) {
        write(gLogFd, header, strlen(header));
    }

    void *callstack[128];
    int frames = backtrace(callstack, 128);

    backtrace_symbols_fd(callstack, frames, STDERR_FILENO);
    if (gLogFd >= 0) {
        backtrace_symbols_fd(callstack, frames, gLogFd);
        const char *footer = "--- End of Stack Trace ---\n";
        write(gLogFd, footer, strlen(footer));
        fsync(gLogFd);
    }

    _exit(128 + sig);
}

static void MPUncaughtExceptionHandler(NSException *exception) {
    NSString *crashDetails = [NSString stringWithFormat:
        @"\n[CRASH] Uncaught Exception: %@\nReason: %@\nCall Stack:\n%@\n",
        exception.name,
        exception.reason,
        [exception.callStackSymbols componentsJoinedByString:@"\n"]];

    MPLog(@"%@", crashDetails);
    if (gLogFd >= 0) {
        fsync(gLogFd);
    }
}

void MPLog(NSString *format, ...) {
    if (!format) return;

    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *ts = [df stringFromDate:[NSDate date]];
    [df release];

    NSString *line = [[NSString alloc] initWithFormat:@"[%@] %@\n", ts, body];
    [body release];

    const char *utf8 = [line UTF8String];
    if (utf8) {
        write(STDERR_FILENO, utf8, strlen(utf8));
        if (gLogFd >= 0) {
            write(gLogFd, utf8, strlen(utf8));
        }
    }
    [line release];
}

@implementation Logger

+ (void)setupLogging {
    NSString *home = NSHomeDirectory();
    NSString *logsDir = [home stringByAppendingPathComponent:@"Library/Logs/MiniPadle"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    gLogFilePath = [[logsDir stringByAppendingPathComponent:@"minipadle.log"] copy];

    gLogFd = open([gLogFilePath UTF8String], O_WRONLY | O_CREAT | O_APPEND, 0644);

    // Also link/mirror into current working directory for easy access
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    if (cwd && [cwd length] > 0) {
        NSString *cwdLog = [cwd stringByAppendingPathComponent:@"minipadle.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:cwdLog]) {
            [[NSFileManager defaultManager] createSymbolicLinkAtPath:cwdLog
                                                 withDestinationPath:gLogFilePath
                                                               error:nil];
        }
    }

    // Install uncaught exception handler
    NSSetUncaughtExceptionHandler(&MPUncaughtExceptionHandler);

    // Install signal handlers
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = MPSignalHandler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESETHAND;

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);

    MPLog(@"==========================================");
    MPLog(@"MiniPadle started (PID: %d)", getpid());
    MPLog(@"Log file: %@", gLogFilePath);
    MPLog(@"==========================================");
}

+ (NSString *)logFilePath {
    return gLogFilePath;
}

+ (void)openLogFile {
    if (gLogFilePath) {
        NSURL *url = [NSURL fileURLWithPath:gLogFilePath];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

@end
