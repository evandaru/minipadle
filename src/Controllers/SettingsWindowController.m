#import "SettingsWindowController.h"

NSString * const MiniPadleSettingsChangedNotification = @"MiniPadleSettingsChangedNotification";

@interface SettingsWindowController () {
    NSSegmentedControl *_themeControl;
    NSPopUpButton *_fontPopup;
    NSSlider *_fontSizeSlider;
    NSTextField *_fontSizeLabel;
    NSSlider *_lineSpacingSlider;
    NSTextField *_lineSpacingLabel;
    NSButton *_wordWrapCheck;
    NSButton *_autosaveCheck;
}
@end

@implementation SettingsWindowController

+ (instancetype)sharedController {
    static SettingsWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SettingsWindowController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 460, 310);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"Preferences";
    [win center];

    if ((self = [super initWithWindow:win])) {
        NSView *content = [[NSView alloc] initWithFrame:frame];

        // --- 1. Theme (Appearance) ---
        NSTextField *themeLabel = [NSTextField labelWithString:@"Theme:"];
        themeLabel.frame = NSMakeRect(30, 260, 110, 20);
        themeLabel.alignment = NSTextAlignmentRight;
        themeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        [content addSubview:themeLabel];

        self->_themeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Dark", @"Light"]
                                                                trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                      target:self
                                                                      action:@selector(settingChanged:)];
        self->_themeControl.frame = NSMakeRect(150, 257, 160, 26);
        BOOL isDark = YES;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleDarkMode"]) {
            isDark = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleDarkMode"];
        } else if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniCodeDarkMode"]) {
            isDark = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniCodeDarkMode"];
        }
        self->_themeControl.selectedSegment = isDark ? 0 : 1;
        [content addSubview:self->_themeControl];

        // --- 2. Font Family ---
        NSTextField *fontLabel = [NSTextField labelWithString:@"Font Family:"];
        fontLabel.frame = NSMakeRect(30, 218, 110, 20);
        fontLabel.alignment = NSTextAlignmentRight;
        fontLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        [content addSubview:fontLabel];

        self->_fontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 215, 180, 26) pullsDown:NO];
        NSArray *fonts = @[@"Menlo", @"Monaco", @"SF Mono", @"Courier", @"Helvetica"];
        [self->_fontPopup addItemsWithTitles:fonts];
        self->_fontPopup.target = self;
        self->_fontPopup.action = @selector(settingChanged:);
        NSString *savedFont = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiniPadleFontName"] ?:
                              [[NSUserDefaults standardUserDefaults] stringForKey:@"MiniCodeFontName"] ?: @"Menlo";
        [self->_fontPopup selectItemWithTitle:savedFont];
        [content addSubview:self->_fontPopup];

        // --- 3. Font Size ---
        NSTextField *sizeLabel = [NSTextField labelWithString:@"Font Size:"];
        sizeLabel.frame = NSMakeRect(30, 175, 110, 20);
        sizeLabel.alignment = NSTextAlignmentRight;
        sizeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        [content addSubview:sizeLabel];

        double currentSize = 13.5;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleFontSize"]) {
            currentSize = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleFontSize"];
        } else if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniCodeFontSize"]) {
            currentSize = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniCodeFontSize"];
        }

        self->_fontSizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(150, 173, 160, 22)];
        self->_fontSizeSlider.minValue = 10.0;
        self->_fontSizeSlider.maxValue = 26.0;
        self->_fontSizeSlider.doubleValue = currentSize;
        self->_fontSizeSlider.target = self;
        self->_fontSizeSlider.action = @selector(settingChanged:);
        [content addSubview:self->_fontSizeSlider];

        self->_fontSizeLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%.0f pt", currentSize]];
        self->_fontSizeLabel.frame = NSMakeRect(320, 175, 60, 20);
        self->_fontSizeLabel.font = [NSFont systemFontOfSize:12];
        [content addSubview:self->_fontSizeLabel];

        // --- 4. Line Spacing (Jarak Line) ---
        NSTextField *lineLabel = [NSTextField labelWithString:@"Line Spacing:"];
        lineLabel.frame = NSMakeRect(30, 132, 110, 20);
        lineLabel.alignment = NSTextAlignmentRight;
        lineLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        [content addSubview:lineLabel];

        double currentLineSpacing = 4.0;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleLineSpacing"]) {
            currentLineSpacing = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleLineSpacing"];
        }

        self->_lineSpacingSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(150, 130, 160, 22)];
        self->_lineSpacingSlider.minValue = 0.0;
        self->_lineSpacingSlider.maxValue = 16.0;
        self->_lineSpacingSlider.doubleValue = currentLineSpacing;
        self->_lineSpacingSlider.target = self;
        self->_lineSpacingSlider.action = @selector(settingChanged:);
        [content addSubview:self->_lineSpacingSlider];

        self->_lineSpacingLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%.0f pt", currentLineSpacing]];
        self->_lineSpacingLabel.frame = NSMakeRect(320, 132, 60, 20);
        self->_lineSpacingLabel.font = [NSFont systemFontOfSize:12];
        [content addSubview:self->_lineSpacingLabel];

        // --- 5. Word Wrap ---
        self->_wordWrapCheck = [NSButton checkboxWithTitle:@"Enable Word Wrap (Soft wrap)" target:self action:@selector(settingChanged:)];
        self->_wordWrapCheck.frame = NSMakeRect(150, 88, 250, 20);
        BOOL wordWrap = YES;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleWordWrap"]) {
            wordWrap = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleWordWrap"];
        }
        self->_wordWrapCheck.state = wordWrap ? NSControlStateValueOn : NSControlStateValueOff;
        [content addSubview:self->_wordWrapCheck];

        // --- 6. Autosave ---
        self->_autosaveCheck = [NSButton checkboxWithTitle:@"Enable Autosave (0.4s debounce)" target:self action:@selector(settingChanged:)];
        self->_autosaveCheck.frame = NSMakeRect(150, 52, 250, 20);
        BOOL autosave = YES;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleAutosave"]) {
            autosave = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleAutosave"];
        } else if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniCodeAutosave"]) {
            autosave = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniCodeAutosave"];
        }
        self->_autosaveCheck.state = autosave ? NSControlStateValueOn : NSControlStateValueOff;
        [content addSubview:self->_autosaveCheck];

        win.contentView = content;
    }
    return self;
}

- (void)settingChanged:(id)sender {
    BOOL isDark = (self->_themeControl.selectedSegment == 0);
    NSString *fontName = self->_fontPopup.titleOfSelectedItem ?: @"Menlo";
    double fontSize = round(self->_fontSizeSlider.doubleValue);
    double lineSpacing = round(self->_lineSpacingSlider.doubleValue);
    BOOL wordWrap = (self->_wordWrapCheck.state == NSControlStateValueOn);
    BOOL autosave = (self->_autosaveCheck.state == NSControlStateValueOn);

    self->_fontSizeLabel.stringValue = [NSString stringWithFormat:@"%.0f pt", fontSize];
    self->_lineSpacingLabel.stringValue = [NSString stringWithFormat:@"%.0f pt", lineSpacing];

    [[NSUserDefaults standardUserDefaults] setBool:isDark forKey:@"MiniPadleDarkMode"];
    [[NSUserDefaults standardUserDefaults] setObject:fontName forKey:@"MiniPadleFontName"];
    [[NSUserDefaults standardUserDefaults] setDouble:fontSize forKey:@"MiniPadleFontSize"];
    [[NSUserDefaults standardUserDefaults] setDouble:lineSpacing forKey:@"MiniPadleLineSpacing"];
    [[NSUserDefaults standardUserDefaults] setBool:wordWrap forKey:@"MiniPadleWordWrap"];
    [[NSUserDefaults standardUserDefaults] setBool:autosave forKey:@"MiniPadleAutosave"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:MiniPadleSettingsChangedNotification object:nil];
}

@end
