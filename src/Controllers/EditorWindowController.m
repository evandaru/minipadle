#import "EditorWindowController.h"
#import "Logger.h"
#import "SettingsWindowController.h"
#import <malloc/malloc.h>

static NSString * const kUntitledTabToken = @"__untitled__";
static NSString * const kLastOpenedFolderKey = @"MiniPadleLastOpenedFolder";

static NSImage *sFolderIcon = nil;
static NSMutableDictionary<NSString *, NSImage *> *sExtensionIconCache = nil;

@implementation EditorWindowController

+ (NSImage *)cachedIconForNode:(FileNode *)node {
    if (!node) return nil;
    if (node->_isDir) {
        if (!sFolderIcon) {
            sFolderIcon = [[NSImage imageNamed:NSImageNameFolder] retain];
            sFolderIcon.size = NSMakeSize(15, 15);
        }
        return sFolderIcon;
    }

    if (!sExtensionIconCache) {
        sExtensionIconCache = [[NSMutableDictionary alloc] initWithCapacity:16];
    }

    NSString *ext = [node->_name pathExtension].lowercaseString;
    if (ext.length == 0) ext = @"__none__";

    NSImage *cached = [sExtensionIconCache objectForKey:ext];
    if (!cached) {
        if ([ext isEqualToString:@"__none__"]) {
            cached = [[NSWorkspace sharedWorkspace] iconForFileType:@"txt"];
        } else {
            cached = [[NSWorkspace sharedWorkspace] iconForFileType:ext];
        }
        if (cached) {
            cached.size = NSMakeSize(15, 15);
            [sExtensionIconCache setObject:cached forKey:ext];
        }
    }
    return cached;
}

+ (NSImage *)cachedIconForPath:(NSString *)path {
    if (!path || [path isEqualToString:kUntitledTabToken]) {
        return [[NSWorkspace sharedWorkspace] iconForFileType:@"txt"];
    }
    if (!sExtensionIconCache) {
        sExtensionIconCache = [[NSMutableDictionary alloc] initWithCapacity:16];
    }
    NSString *ext = [path pathExtension].lowercaseString;
    if (ext.length == 0) ext = @"__none__";
    NSImage *cached = [sExtensionIconCache objectForKey:ext];
    if (!cached) {
        cached = [[NSWorkspace sharedWorkspace] iconForFileType:ext];
        if (cached) {
            cached.size = NSMakeSize(14, 14);
            [sExtensionIconCache setObject:cached forKey:ext];
        }
    }
    return cached;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 960, 640);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"MiniPadle";
    [win center];

    win.tabbingMode = NSWindowTabbingModeDisallowed;
    [NSWindow setAllowsAutomaticWindowTabbing:NO];

    if ((self = [super initWithWindow:win])) {
        self->_fontName = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiniPadleFontName"] ?: @"Menlo";
        self->_fontSize = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleFontSize"];
        if (self->_fontSize < 10.0) self->_fontSize = 13.5;

        self->_lineSpacing = 4.0;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleLineSpacing"]) {
            self->_lineSpacing = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleLineSpacing"];
        }

        self->_uiScale = 1.0;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleUIScale"]) {
            self->_uiScale = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleUIScale"];
            if (self->_uiScale < 0.8 || self->_uiScale > 1.5) self->_uiScale = 1.0;
        }

        self->_wordWrapEnabled = YES;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleWordWrap"]) {
            self->_wordWrapEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleWordWrap"];
        }

        self->_autosaveEnabled = YES;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleAutosave"]) {
            self->_autosaveEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleAutosave"];
        }

        self->_isDarkMode = YES;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleDarkMode"]) {
            self->_isDarkMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleDarkMode"];
        }

        self->_showHiddenFiles = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleShowHiddenFiles"];
        self->_lastSidebarWidth = 230.0;

        [self updateFont];

        self->_splitView = [[NSSplitView alloc] initWithFrame:frame];
        self->_splitView.vertical = YES;
        self->_splitView.dividerStyle = NSSplitViewDividerStyleThin;
        self->_splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self->_splitView.delegate = self;

        // --- Sidebar (Left Pane) ---
        self->_leftContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 230, 640)];
        self->_leftContainer.autoresizingMask = NSViewHeightSizable;

        NSScrollView *outlineScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 230, 640)];
        outlineScroll.hasVerticalScroller = YES;
        outlineScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        self->_outlineView = [[NSOutlineView alloc] initWithFrame:outlineScroll.bounds];
        self->_outlineView.headerView = nil;
        self->_outlineView.rowHeight = round(24.0 * self->_uiScale);

        [self->_outlineView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        [self->_outlineView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"Col"];
        col.width = 220;
        [self->_outlineView addTableColumn:col];
        self->_outlineView.outlineTableColumn = col;
        outlineScroll.documentView = self->_outlineView;
        [self->_leftContainer addSubview:outlineScroll];

        // Sidebar Empty Placeholder
        self->_sidebarEmptyView = [[NSView alloc] initWithFrame:outlineScroll.frame];
        self->_sidebarEmptyView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        CGFloat sWidth = outlineScroll.frame.size.width;
        CGFloat sHeight = outlineScroll.frame.size.height;
        NSView *centerSidebarBox = [[NSView alloc] initWithFrame:NSMakeRect(15, (sHeight - 120) / 2.0, sWidth - 30, 120)];
        centerSidebarBox.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;

        NSTextField *emptyTitle = [NSTextField labelWithString:@"No Folder Open"];
        emptyTitle.frame = NSMakeRect(0, 80, centerSidebarBox.frame.size.width, 22);
        emptyTitle.alignment = NSTextAlignmentCenter;
        emptyTitle.textColor = [NSColor secondaryLabelColor];
        emptyTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        emptyTitle.autoresizingMask = NSViewWidthSizable;
        [centerSidebarBox addSubview:emptyTitle];

        NSTextField *emptySub = [NSTextField labelWithString:@"Open a folder to browse files"];
        emptySub.frame = NSMakeRect(0, 56, centerSidebarBox.frame.size.width, 18);
        emptySub.alignment = NSTextAlignmentCenter;
        emptySub.textColor = [NSColor tertiaryLabelColor];
        emptySub.font = [NSFont systemFontOfSize:11];
        emptySub.autoresizingMask = NSViewWidthSizable;
        [centerSidebarBox addSubview:emptySub];

        NSButton *sideOpenBtn = [NSButton buttonWithTitle:@"Open Folder..." target:self action:@selector(openFolderDialog)];
        sideOpenBtn.frame = NSMakeRect((centerSidebarBox.frame.size.width - 130) / 2.0, 14, 130, 28);
        sideOpenBtn.bezelStyle = NSBezelStyleRounded;
        sideOpenBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        sideOpenBtn.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
        [centerSidebarBox addSubview:sideOpenBtn];

        [self->_sidebarEmptyView addSubview:centerSidebarBox];
        self->_sidebarEmptyView.hidden = YES;
        [self->_leftContainer addSubview:self->_sidebarEmptyView];

        [self->_splitView addSubview:self->_leftContainer];

        // --- Editor Container (Right Pane) ---
        self->_rightContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 730, 640)];
        self->_rightContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        self->_openTabs = [NSMutableArray new];
        self->_activeTabIndex = -1;

        CGFloat tabHeight = round(36.0 * self->_uiScale);
        self->_tabBarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 640 - tabHeight, 730, tabHeight)];
        self->_tabBarContainer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        self->_tabBarContainer.wantsLayer = YES;

        // Tombol Main Menu di ujung kanan Tab Bar
        self->_mainMenuBtn = [NSButton buttonWithTitle:@"Main Menu" target:self action:@selector(goToMainMenu)];
        self->_mainMenuBtn.frame = NSMakeRect(730 - 95, (tabHeight - 24) / 2.0, 88, 24);
        self->_mainMenuBtn.bezelStyle = NSBezelStyleInline;
        self->_mainMenuBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        self->_mainMenuBtn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
        [self->_tabBarContainer addSubview:self->_mainMenuBtn];

        self->_tabScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 730 - 100, tabHeight)];
        self->_tabScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self->_tabScrollView.hasHorizontalScroller = NO;
        self->_tabScrollView.hasVerticalScroller = NO;
        self->_tabScrollView.drawsBackground = NO;

        self->_tabBarView = [[NSView alloc] initWithFrame:self->_tabScrollView.bounds];
        self->_tabScrollView.documentView = self->_tabBarView;
        [self->_tabBarContainer addSubview:self->_tabScrollView];
        [self->_rightContainer addSubview:self->_tabBarContainer];

        self->_textScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 26, 730, 640 - tabHeight - 26)];
        self->_textScroll.hasVerticalScroller = YES;
        self->_textScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        NSSize contentSize = [self->_textScroll contentSize];
        self->_textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        self->_textView.minSize = NSMakeSize(0.0, contentSize.height);
        self->_textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        self->_textView.verticallyResizable = YES;

        self->_textView.delegate = self;
        self->_textView.richText = NO;
        self->_textView.automaticQuoteSubstitutionEnabled = NO;
        self->_textView.automaticDashSubstitutionEnabled = NO;
        self->_textView.automaticSpellingCorrectionEnabled = NO;
        self->_textView.textContainerInset = NSMakeSize(14, 14);
        self->_textView.font = self->_editorFont;
        self->_textView.usesFindBar = YES;

        self->_textScroll.documentView = self->_textView;
        [self->_rightContainer addSubview:self->_textScroll];

        self->_statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 3, 702, 20)];
        self->_statusLabel.editable = NO;
        self->_statusLabel.bordered = NO;
        self->_statusLabel.backgroundColor = [NSColor clearColor];
        self->_statusLabel.font = [NSFont monospacedDigitSystemFontOfSize:round(11 * self->_uiScale) weight:NSFontWeightRegular];
        self->_statusLabel.stringValue = @"Ready";
        self->_statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [self->_rightContainer addSubview:self->_statusLabel];

        [self->_splitView addSubview:self->_rightContainer];
        [self->_splitView setPosition:230 ofDividerAtIndex:0];
        [self->_splitView adjustSubviews];
        win.contentView = self->_splitView;

        self->_outlineView.menu = [self buildContextMenu];

        self->_quickOpenController = [[QuickOpenWindowController alloc] init];
        self->_quickOpenController.delegate = self;

        self->_outlineView.dataSource = self;
        self->_outlineView.delegate = self;

        [self applyWordWrap];
        [self applyLineSpacing];
        [self applyTheme];

        NSString *lastFolder = [[NSUserDefaults standardUserDefaults] stringForKey:kLastOpenedFolderKey];
        BOOL isDir = NO;
        if (lastFolder && [[NSFileManager defaultManager] fileExistsAtPath:lastFolder isDirectory:&isDir] && isDir) {
            [self openFolderAtPath:lastFolder];
        } else {
            [self showWelcomeScreenIfNeeded];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleSettingsChanged:)
                                                     name:MiniPadleSettingsChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self->_saveTimer) {
        [self->_saveTimer invalidate];
        self->_saveTimer = nil;
    }
    [self->_currentFilePath release];
    [self->_rootPath release];
    [self->_rootNode release];
    [self->_quickOpenController release];
    [self->_openTabs release];
    [self->_welcomeView release];
    [self->_sidebarEmptyView release];
    [super dealloc];
}

#pragma mark - Toggle Sidebar (Hidden Sidebar)

- (void)toggleSidebar {
    BOOL isHidden = self->_leftContainer.isHidden || [self->_splitView isSubviewCollapsed:self->_leftContainer];
    if (isHidden) {
        self->_leftContainer.hidden = NO;
        CGFloat targetW = self->_lastSidebarWidth > 120.0 ? self->_lastSidebarWidth : 230.0;
        [self->_splitView setPosition:targetW ofDividerAtIndex:0];
    } else {
        self->_lastSidebarWidth = self->_leftContainer.frame.size.width;
        self->_leftContainer.hidden = YES;
        [self->_splitView setPosition:0 ofDividerAtIndex:0];
    }
    [self->_splitView adjustSubviews];
    [self applyWordWrap];
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    return (subview == self->_leftContainer);
}

- (CGFloat)splitView:(NSSplitView *)splitView minPossiblePositionOfDividerAtIndex:(NSInteger)idx {
    return 140.0;
}

#pragma mark - Main Menu / Home Action

- (void)goToMainMenu {
    [self saveCurrentFile];

    [self->_currentFilePath release];
    self->_currentFilePath = nil;
    [self->_rootPath release];
    self->_rootPath = nil;
    [self->_rootNode release];
    self->_rootNode = nil;

    [self->_openTabs removeAllObjects];
    self->_activeTabIndex = -1;
    self->_textView.string = @"";

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLastOpenedFolderKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    self.window.title = @"MiniPadle";
    [self->_outlineView reloadData];
    [self renderTabs];
    [self showWelcomeScreenIfNeeded];
}

#pragma mark - Toggle Show Hidden Files

- (void)toggleShowHiddenFiles {
    self->_showHiddenFiles = !self->_showHiddenFiles;
    [[NSUserDefaults standardUserDefaults] setBool:self->_showHiddenFiles forKey:@"MiniPadleShowHiddenFiles"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (self->_rootNode) {
        [self->_rootNode updateShowHiddenRecursively:self->_showHiddenFiles];
        [self->_outlineView reloadData];
    }
    self->_statusLabel.stringValue = self->_showHiddenFiles ? @"Showing hidden files" : @"Hiding hidden files";
}

#pragma mark - Obsidian Style Welcome Screen

- (void)showWelcomeScreenIfNeeded {
    if (self->_rootPath != nil) {
        if (self->_welcomeView) {
            [self->_welcomeView removeFromSuperview];
            self->_welcomeView = nil;
        }
        self->_sidebarEmptyView.hidden = YES;
        self->_textScroll.hidden = NO;
        self->_tabBarContainer.hidden = NO;
        return;
    }

    self->_sidebarEmptyView.hidden = NO;
    self->_textScroll.hidden = YES;
    self->_tabBarContainer.hidden = YES;

    if (!self->_welcomeView) {
        self->_welcomeView = [[NSView alloc] initWithFrame:self->_rightContainer.bounds];
        self->_welcomeView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        CGFloat cx = (self->_rightContainer.bounds.size.width - 400) / 2.0;
        CGFloat cy = (self->_rightContainer.bounds.size.height - 360) / 2.0;
        NSView *centerBox = [[NSView alloc] initWithFrame:NSMakeRect(cx, cy, 400, 360)];
        centerBox.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;

        NSTextField *logoTitle = [NSTextField labelWithString:@"MiniPadle"];
        logoTitle.frame = NSMakeRect(0, 305, 400, 36);
        logoTitle.alignment = NSTextAlignmentCenter;
        logoTitle.font = [NSFont systemFontOfSize:26 weight:NSFontWeightBold];
        [centerBox addSubview:logoTitle];

        NSTextField *subTitle = [NSTextField labelWithString:@"Ultra-slim, fast & distraction-free editor"];
        subTitle.frame = NSMakeRect(0, 275, 400, 20);
        subTitle.alignment = NSTextAlignmentCenter;
        subTitle.textColor = [NSColor secondaryLabelColor];
        subTitle.font = [NSFont systemFontOfSize:13];
        [centerBox addSubview:subTitle];

        NSButton *openBtn = [NSButton buttonWithTitle:@"Open Folder..." target:self action:@selector(openFolderDialog)];
        openBtn.frame = NSMakeRect(75, 215, 250, 34);
        openBtn.bezelStyle = NSBezelStyleRounded;
        openBtn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        [centerBox addSubview:openBtn];

        NSButton *noteBtn = [NSButton buttonWithTitle:@"New Note" target:self action:@selector(newUntitledNote)];
        noteBtn.frame = NSMakeRect(75, 170, 250, 34);
        noteBtn.bezelStyle = NSBezelStyleRounded;
        noteBtn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        [centerBox addSubview:noteBtn];

        NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:@"MiniPadleRecentFolders"];
        if (recents && recents.count > 0) {
            NSTextField *recentHeader = [NSTextField labelWithString:@"Recent Workspaces:"];
            recentHeader.frame = NSMakeRect(75, 130, 250, 20);
            recentHeader.textColor = [NSColor secondaryLabelColor];
            recentHeader.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
            [centerBox addSubview:recentHeader];

            CGFloat ry = 100;
            NSInteger limit = MIN((NSInteger)recents.count, 3);
            for (NSInteger i = 0; i < limit; i++) {
                NSString *folderPath = recents[i];
                NSButton *recBtn = [NSButton buttonWithTitle:[folderPath lastPathComponent]
                                                      target:self
                                                      action:@selector(recentFolderClicked:)];
                recBtn.frame = NSMakeRect(75, ry, 250, 26);
                recBtn.bezelStyle = NSBezelStyleInline;
                recBtn.toolTip = folderPath;
                [centerBox addSubview:recBtn];
                ry -= 30;
            }
        }

        [self->_welcomeView addSubview:centerBox];
        [self->_rightContainer addSubview:self->_welcomeView];
    }
}

- (void)recentFolderClicked:(NSButton *)sender {
    if (sender.toolTip) {
        [self openFolderAtPath:sender.toolTip];
    }
}

#pragma mark - Word Wrap & Line Spacing

- (void)applyWordWrap {
    if (!self->_textView || !self->_textScroll) return;

    NSClipView *clipView = [self->_textScroll contentView];
    CGFloat contentWidth = [self->_textScroll contentSize].width;

    if (self->_wordWrapEnabled) {
        [self->_textScroll setHasHorizontalScroller:NO];

        NSPoint currentOrigin = clipView.bounds.origin;
        currentOrigin.x = 0;
        [clipView scrollToPoint:currentOrigin];
        [self->_textScroll reflectScrolledClipView:clipView];

        [self->_textView setHorizontallyResizable:NO];
        [self->_textView setAutoresizingMask:NSViewWidthSizable];

        NSRect textFrame = self->_textView.frame;
        textFrame.size.width = contentWidth;
        self->_textView.frame = textFrame;

        CGFloat insetWidth = self->_textView.textContainerInset.width * 2.0;
        CGFloat containerWidth = MAX(10.0, contentWidth - insetWidth);

        self->_textView.textContainer.containerSize = NSMakeSize(containerWidth, CGFLOAT_MAX);
        self->_textView.textContainer.widthTracksTextView = YES;
    } else {
        [self->_textScroll setHasHorizontalScroller:YES];
        [self->_textView setHorizontallyResizable:YES];
        [self->_textView setAutoresizingMask:NSViewNotSizable];
        self->_textView.textContainer.widthTracksTextView = NO;
        self->_textView.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    }

    [self->_textView sizeToFit];
}

- (void)applyLineSpacing {
    if (!self->_textView) return;

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = self->_lineSpacing;
    self->_textView.defaultParagraphStyle = style;

    if (self->_textView.textStorage.length > 0) {
        [self->_textView.textStorage addAttribute:NSParagraphStyleAttributeName
                                            value:style
                                            range:NSMakeRange(0, self->_textView.textStorage.length)];
    }
    [style release];
}

#pragma mark - Untitled Note & Tab Management

- (BOOL)isUntitledTab:(NSString *)tabPath {
    return [tabPath isEqualToString:kUntitledTabToken];
}

- (void)newUntitledNote {
    [self saveCurrentFile];

    if (self->_welcomeView) {
        [self->_welcomeView removeFromSuperview];
        self->_welcomeView = nil;
    }
    self->_textScroll.hidden = NO;
    self->_tabBarContainer.hidden = NO;

    [self->_openTabs addObject:kUntitledTabToken];
    self->_activeTabIndex = self->_openTabs.count - 1;

    [self->_currentFilePath release];
    self->_currentFilePath = nil;

    self->_textView.string = @"";
    self->_textView.font = self->_editorFont;
    [self applyLineSpacing];

    [self renderTabs];
    [self updateStatusInfo];
    [self.window makeFirstResponder:self->_textView];
}

- (void)closeActiveTab {
    if (self->_activeTabIndex >= 0) {
        [self closeTabAtIndex:self->_activeTabIndex];
    }
}

- (void)closeTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self->_openTabs.count) return;

    NSString *tabPath = self->_openTabs[index];

    if ([self isUntitledTab:tabPath]) {
        NSString *content = self->_textView.string;
        NSString *trimmed = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Do you want to save changes to Untitled?";
            alert.informativeText = @"Your changes will be lost if you don't save them.";
            [alert addButtonWithTitle:@"Save..."];
            [alert addButtonWithTitle:@"Don't Save"];
            [alert addButtonWithTitle:@"Cancel"];

            NSModalResponse res = [alert runModal];
            if (res == NSAlertFirstButtonReturn) {
                [self saveCurrentFileAs];
                if (!self->_currentFilePath) {
                    return;
                }
            } else if (res == NSAlertThirdButtonReturn) {
                return;
            }
        }
    } else {
        [self saveCurrentFile];
    }

    BOOL wasActive = (index == self->_activeTabIndex);
    [self->_openTabs removeObjectAtIndex:index];

    if (self->_openTabs.count == 0) {
        self->_activeTabIndex = -1;
        [self->_currentFilePath release];
        self->_currentFilePath = nil;
        self->_textView.string = @"";
        if (!self->_rootPath) {
            [self showWelcomeScreenIfNeeded];
        }
    } else if (wasActive) {
        NSInteger newIdx = index;
        if (newIdx >= (NSInteger)self->_openTabs.count) {
            newIdx = self->_openTabs.count - 1;
        }
        self->_activeTabIndex = newIdx;
        NSString *newPath = self->_openTabs[newIdx];
        if ([self isUntitledTab:newPath]) {
            [self->_currentFilePath release];
            self->_currentFilePath = nil;
        } else {
            [self openFile:newPath];
        }
    } else if (self->_activeTabIndex > index) {
        self->_activeTabIndex--;
    }

    [self renderTabs];
    [self updateStatusInfo];
}

- (void)saveCurrentFile {
    if (self->_saveTimer) {
        [self->_saveTimer invalidate];
        self->_saveTimer = nil;
    }

    if (!self->_currentFilePath) {
        return;
    }

    NSError *err = nil;
    NSString *textToSave = self->_textView.string ?: @"";
    BOOL ok = [textToSave writeToFile:self->_currentFilePath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (ok) {
        [self updateStatusInfo];
        MPLog(@"Saved file: %@", self->_currentFilePath);
    } else if (err) {
        self->_statusLabel.stringValue = @"Error saving file";
        MPLog(@"Error saving file %@: %@", self->_currentFilePath, err.localizedDescription);
    }
}

- (void)saveCurrentFileAs {
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (self->_rootPath) {
        panel.directoryURL = [NSURL fileURLWithPath:self->_rootPath];
    }
    panel.nameFieldStringValue = @"notes.txt";

    if ([panel runModal] == NSModalResponseOK) {
        NSString *chosenPath = panel.URL.path;
        if (chosenPath) {
            NSError *err = nil;
            [self->_textView.string writeToFile:chosenPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
            if (!err) {
                if (self->_activeTabIndex >= 0 && self->_activeTabIndex < (NSInteger)self->_openTabs.count) {
                    [self->_openTabs replaceObjectAtIndex:self->_activeTabIndex withObject:chosenPath];
                }
                [self->_currentFilePath release];
                self->_currentFilePath = [chosenPath copy];
                [self openFolderAtPath:self->_rootPath ?: [chosenPath stringByDeletingLastPathComponent]];
                [self renderTabs];
                [self updateStatusInfo];
            }
        }
    }
}

- (void)textDidChange:(NSNotification *)n {
    if (self->_openTabs.count == 0) {
        [self->_openTabs addObject:kUntitledTabToken];
        self->_activeTabIndex = 0;
        [self renderTabs];
    }

    [self updateStatusInfo];

    if (self->_autosaveEnabled && self->_currentFilePath) {
        if (self->_saveTimer) {
            [self->_saveTimer invalidate];
            self->_saveTimer = nil;
        }
        self->_saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                            target:self
                                                          selector:@selector(autosaveTimerFired:)
                                                          userInfo:nil
                                                           repeats:NO];
    }
}

- (void)autosaveTimerFired:(NSTimer *)timer {
    self->_saveTimer = nil;
    [self saveCurrentFile];
}

#pragma mark - Context Menu

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"FileActions"];
    menu.delegate = self;

    [menu addItemWithTitle:@"New File..." action:@selector(createNewFile) keyEquivalent:@""];
    [menu addItemWithTitle:@"New Folder..." action:@selector(createNewFolder) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];

    NSString *hiddenTitle = self->_showHiddenFiles ? @"Hide Hidden Files" : @"Show Hidden Files";
    [menu addItemWithTitle:hiddenTitle action:@selector(toggleShowHiddenFiles) keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Rename..." action:@selector(renameSelectedItem) keyEquivalent:@""];
    [menu addItemWithTitle:@"Delete" action:@selector(deleteSelectedItem) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Cut" action:@selector(cutSelectedItem) keyEquivalent:@""];
    [menu addItemWithTitle:@"Copy" action:@selector(copySelectedItem) keyEquivalent:@""];
    [menu addItemWithTitle:@"Paste" action:@selector(pasteIntoSelectedItem) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Copy Full Path" action:@selector(copyPathSelectedItem) keyEquivalent:@""];
    [menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealSelectedItemInFinder) keyEquivalent:@""];

    return menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSInteger clicked = [self->_outlineView clickedRow];
    if (clicked >= 0) {
        [self->_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:clicked] byExtendingSelection:NO];
    }
}

- (FileNode *)selectedNode {
    NSInteger row = [self->_outlineView selectedRow];
    if (row >= 0) {
        return [self->_outlineView itemAtRow:row];
    }
    return nil;
}

- (void)renameSelectedItem {
    FileNode *node = [self selectedNode];
    if (!node || !node->_path) return;

    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Rename %@", node->_isDir ? @"Folder" : @"File"];
    alert.informativeText = @"Enter new name:";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.stringValue = node->_name ?: @"";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *newName = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length > 0 && ![newName isEqualToString:node->_name]) {
            NSString *parentDir = [node->_path stringByDeletingLastPathComponent];
            NSString *newPath = [parentDir stringByAppendingPathComponent:newName];
            NSError *err = nil;
            BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:node->_path toPath:newPath error:&err];
            if (!ok && err) {
                NSAlert *errAlert = [NSAlert alertWithError:err];
                [errAlert runModal];
            } else {
                if ([self->_currentFilePath isEqualToString:node->_path]) {
                    self->_currentFilePath = [newPath copy];
                    NSInteger tIdx = [self->_openTabs indexOfObject:node->_path];
                    if (tIdx != NSNotFound) [self->_openTabs replaceObjectAtIndex:tIdx withObject:newPath];
                    [self renderTabs];
                }
                [self openFolderAtPath:self->_rootPath];
            }
        }
    }
}

- (void)deleteSelectedItem {
    FileNode *node = [self selectedNode];
    if (!node || !node->_path) return;

    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Move \"%@\" to Trash?", node->_name];
    alert.informativeText = @"You can restore it from macOS Trash if needed.";
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSError *err = nil;
        NSURL *url = [NSURL fileURLWithPath:node->_path];
        BOOL ok = [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:nil error:&err];
        if (!ok && err) {
            NSAlert *errAlert = [NSAlert alertWithError:err];
            [errAlert runModal];
        } else {
            if ([self->_currentFilePath isEqualToString:node->_path]) {
                self->_currentFilePath = nil;
                self->_textView.string = @"";
                NSInteger tIdx = [self->_openTabs indexOfObject:node->_path];
                if (tIdx != NSNotFound) [self closeTabAtIndex:tIdx];
                self->_statusLabel.stringValue = @"Ready";
            }
            [self openFolderAtPath:self->_rootPath];
        }
    }
}

- (void)copySelectedItem {
    FileNode *node = [self selectedNode];
    if (!node || !node->_path) return;

    self->_clipboardPath = [node->_path copy];
    self->_isCutOperation = NO;

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:@[[NSURL fileURLWithPath:node->_path]]];
    self->_statusLabel.stringValue = [NSString stringWithFormat:@"Copied: %@", node->_name];
}

- (void)cutSelectedItem {
    FileNode *node = [self selectedNode];
    if (!node || !node->_path) return;

    self->_clipboardPath = [node->_path copy];
    self->_isCutOperation = YES;
    self->_statusLabel.stringValue = [NSString stringWithFormat:@"Cut: %@", node->_name];
}

- (void)pasteIntoSelectedItem {
    if (!self->_clipboardPath || ![[NSFileManager defaultManager] fileExistsAtPath:self->_clipboardPath]) {
        self->_statusLabel.stringValue = @"Clipboard is empty";
        return;
    }

    NSString *targetDir = [self selectedTargetDirectory];
    NSString *fileName = [self->_clipboardPath lastPathComponent];
    NSString *destPath = [targetDir stringByAppendingPathComponent:fileName];

    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
        NSString *base = [fileName stringByDeletingPathExtension];
        NSString *ext = [fileName pathExtension];
        NSString *dotExt = ext.length > 0 ? [NSString stringWithFormat:@".%@", ext] : @"";
        destPath = [targetDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ copy%@", base, dotExt]];
    }

    NSError *err = nil;
    BOOL ok = NO;
    if (self->_isCutOperation) {
        ok = [[NSFileManager defaultManager] moveItemAtPath:self->_clipboardPath toPath:destPath error:&err];
        self->_isCutOperation = NO;
        self->_clipboardPath = nil;
    } else {
        ok = [[NSFileManager defaultManager] copyItemAtPath:self->_clipboardPath toPath:destPath error:&err];
    }

    if (!ok && err) {
        NSAlert *errAlert = [NSAlert alertWithError:err];
        [errAlert runModal];
    } else {
        self->_statusLabel.stringValue = [NSString stringWithFormat:@"Pasted: %@", [destPath lastPathComponent]];
        [self openFolderAtPath:self->_rootPath];
        [self openFile:destPath];
    }
}

- (void)copyPathSelectedItem {
    FileNode *node = [self selectedNode];
    if (!node || !node->_path) return;

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:node->_path forType:NSPasteboardTypeString];
    self->_statusLabel.stringValue = @"Copied path to clipboard";
}

- (void)revealSelectedItemInFinder {
    FileNode *node = [self selectedNode];
    NSString *target = node ? node->_path : self->_rootPath;
    if (target) {
        [[NSWorkspace sharedWorkspace] selectFile:target inFileViewerRootedAtPath:@""];
    }
}

#pragma mark - Drag & Drop

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)ov pasteboardWriterForItem:(id)item {
    FileNode *node = (FileNode *)item;
    if (!node || !node->_path) return nil;
    return [NSURL fileURLWithPath:node->_path];
}

- (NSDragOperation)outlineView:(NSOutlineView *)ov validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {
    FileNode *targetNode = (FileNode *)item;
    if (!targetNode || targetNode->_isDir) {
        return NSDragOperationMove;
    }
    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)ov acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
    NSPasteboard *pboard = [info draggingPasteboard];
    NSArray<NSURL *> *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
    if (urls.count == 0) return NO;

    NSString *destDir = (item && ((FileNode *)item)->_isDir) ? ((FileNode *)item)->_path : self->_rootPath;
    if (!destDir) return NO;

    for (NSURL *srcURL in urls) {
        NSString *srcPath = srcURL.path;
        if (!srcPath) continue;
        NSString *destPath = [destDir stringByAppendingPathComponent:[srcPath lastPathComponent]];
        if ([srcPath isEqualToString:destPath]) continue;

        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:srcPath toPath:destPath error:&err];
        if (!ok && err) {
            NSAlert *errAlert = [NSAlert alertWithError:err];
            [errAlert runModal];
            return NO;
        }
    }

    [self openFolderAtPath:self->_rootPath];
    return YES;
}

#pragma mark - Preferences & Notifications

- (void)handleSettingsChanged:(NSNotification *)notif {
    self->_isDarkMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleDarkMode"];
    self->_fontName = [[NSUserDefaults standardUserDefaults] stringForKey:@"MiniPadleFontName"] ?: @"Menlo";
    self->_fontSize = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleFontSize"];
    if (self->_fontSize < 10.0) self->_fontSize = 13.5;
    self->_autosaveEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleAutosave"];

    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleLineSpacing"]) {
        self->_lineSpacing = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleLineSpacing"];
    }
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleWordWrap"]) {
        self->_wordWrapEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleWordWrap"];
    }

    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleUIScale"]) {
        self->_uiScale = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MiniPadleUIScale"];
        if (self->_uiScale < 0.8 || self->_uiScale > 1.5) self->_uiScale = 1.0;
        self->_outlineView.rowHeight = round(24.0 * self->_uiScale);
        self->_statusLabel.font = [NSFont monospacedDigitSystemFontOfSize:round(11 * self->_uiScale) weight:NSFontWeightRegular];
    }

    [self updateFont];
    [self applyLineSpacing];
    [self applyWordWrap];
    [self applyTheme];
    [self->_outlineView reloadData];
}

- (void)openSettings {
    SettingsWindowController *settings = [SettingsWindowController sharedController];
    [settings showWindow:nil];
    [settings.window makeKeyAndOrderFront:nil];
}

- (void)updateFont {
    NSFont *font = [NSFont fontWithName:self->_fontName size:self->_fontSize];
    if (!font) {
        font = [NSFont userFixedPitchFontOfSize:self->_fontSize];
    }
    self->_editorFont = font;
    if (self->_textView) {
        self->_textView.font = self->_editorFont;
    }
}

- (void)applyTheme {
    NSColor *bg, *fg, *sideBg;
    if (self->_isDarkMode) {
        self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        bg = [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        fg = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
        sideBg = [NSColor colorWithCalibratedRed:0.09 green:0.09 blue:0.10 alpha:1.0];
    } else {
        self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        bg = [NSColor whiteColor];
        fg = [NSColor colorWithCalibratedWhite:0.15 alpha:1.0];
        sideBg = [NSColor colorWithCalibratedRed:0.95 green:0.96 blue:0.98 alpha:1.0];
    }
    self->_textView.backgroundColor = bg;
    self->_textView.textColor = fg;
    self->_textView.insertionPointColor = fg;
    self->_outlineView.backgroundColor = sideBg;
    self->_tabBarContainer.layer.backgroundColor = (self->_isDarkMode ? [NSColor colorWithCalibratedRed:0.09 green:0.09 blue:0.11 alpha:1.0] : [NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0]).CGColor;
    [self renderTabs];
    [self updateStatusInfo];
}

#pragma mark - Zoom Controls

- (void)zoomIn {
    if (self->_fontSize < 36.0) {
        self->_fontSize += 1.5;
        [[NSUserDefaults standardUserDefaults] setDouble:self->_fontSize forKey:@"MiniPadleFontSize"];
        [self updateFont];
        self->_statusLabel.stringValue = [NSString stringWithFormat:@"Zoom: %.1f pt", self->_fontSize];
    }
}

- (void)zoomOut {
    if (self->_fontSize > 9.0) {
        self->_fontSize -= 1.5;
        [[NSUserDefaults standardUserDefaults] setDouble:self->_fontSize forKey:@"MiniPadleFontSize"];
        [self updateFont];
        self->_statusLabel.stringValue = [NSString stringWithFormat:@"Zoom: %.1f pt", self->_fontSize];
    }
}

- (void)resetZoom {
    self->_fontSize = 13.5;
    [[NSUserDefaults standardUserDefaults] setDouble:self->_fontSize forKey:@"MiniPadleFontSize"];
    [self updateFont];
    self->_statusLabel.stringValue = @"Zoom reset: 13.5 pt";
}

#pragma mark - Quick Open

- (void)showQuickOpen {
    [self->_quickOpenController presentWithRootPath:self->_rootPath isDarkMode:self->_isDarkMode];
}

- (void)quickOpenDidSelectFilePath:(NSString *)filePath {
    [self openFile:filePath];
}

#pragma mark - Folder and File Operations

- (void)openFolderDialog {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] == NSModalResponseOK) {
        [self openFolderAtPath:panel.URL.path];
    }
}

- (void)addRecentFolder:(NSString *)path {
    if (!path || path.length == 0) return;
    NSMutableArray *recent = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"MiniPadleRecentFolders"] mutableCopy] ?: [NSMutableArray new];
    [recent removeObject:path];
    [recent insertObject:path atIndex:0];
    if (recent.count > 10) {
        [recent removeObjectsInRange:NSMakeRange(10, recent.count - 10)];
    }
    [[NSUserDefaults standardUserDefaults] setObject:recent forKey:@"MiniPadleRecentFolders"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MiniPadleRecentFoldersChangedNotification" object:nil];
}

- (void)openFolderAtPath:(NSString *)path {
    if (!path || path.length == 0) return;
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || !isDir) return;

    if (self->_rootPath != path) {
        [self->_rootPath release];
        self->_rootPath = [path copy];
    }
    [self addRecentFolder:path];

    [[NSUserDefaults standardUserDefaults] setObject:path forKey:kLastOpenedFolderKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    MPLog(@"Opened folder: %@", path);
    [self->_quickOpenController preloadRootPath:path];

    [self->_rootNode release];
    self->_rootNode = [[FileNode alloc] initWithPath:path isDir:YES showHidden:self->_showHiddenFiles];
    [self->_rootNode loadChildrenIfNeeded];
    [self->_outlineView reloadData];
    self.window.title = [NSString stringWithFormat:@"MiniPadle - %@", [path lastPathComponent]];

    [self showWelcomeScreenIfNeeded];
    malloc_zone_pressure_relief(malloc_default_zone(), 0);
}

#pragma mark - VS Code Style Tabs

- (void)renderTabs {
    for (NSView *v in [self->_tabBarView.subviews copy]) {
        [v removeFromSuperview];
    }

    CGFloat x = 0;
    CGFloat tabHeight = round(35.0 * self->_uiScale);
    CGFloat barWidth = self->_tabScrollView.bounds.size.width;

    NSColor *activeBg = self->_isDarkMode ? [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.14 alpha:1.0] : [NSColor whiteColor];
    NSColor *inactiveBg = [NSColor clearColor];
    NSColor *activeTextColor = [NSColor labelColor];
    NSColor *inactiveTextColor = [NSColor secondaryLabelColor];
    NSColor *borderColor = self->_isDarkMode ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.08] : [NSColor colorWithCalibratedWhite:0.0 alpha:0.1];
    NSColor *accentColor = [NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:1.0];

    CGFloat tabFontSize = round(12.0 * self->_uiScale);

    for (NSInteger i = 0; i < (NSInteger)self->_openTabs.count; i++) {
        NSString *path = self->_openTabs[i];
        NSString *name = [self isUntitledTab:path] ? @"Untitled" : [path lastPathComponent];
        BOOL isActive = (i == self->_activeTabIndex);

        NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:tabFontSize weight:isActive ? NSFontWeightMedium : NSFontWeightRegular]};
        NSSize nameSize = [name sizeWithAttributes:attrs];
        CGFloat tabWidth = MAX(100.0 * self->_uiScale, MIN(240.0 * self->_uiScale, nameSize.width + 56.0 * self->_uiScale));

        NSView *tab = [[NSView alloc] initWithFrame:NSMakeRect(x, 0, tabWidth, tabHeight)];
        tab.wantsLayer = YES;
        tab.layer.backgroundColor = (isActive ? activeBg : inactiveBg).CGColor;

        if (isActive) {
            NSView *accentLine = [[NSView alloc] initWithFrame:NSMakeRect(0, tabHeight - 2, tabWidth, 2)];
            accentLine.wantsLayer = YES;
            accentLine.layer.backgroundColor = accentColor.CGColor;
            [tab addSubview:accentLine];
            [accentLine release];
        }

        NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(tabWidth - 1, 6, 1, tabHeight - 12)];
        sep.wantsLayer = YES;
        sep.layer.backgroundColor = borderColor.CGColor;
        [tab addSubview:sep];
        [sep release];

        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(8, (tabHeight - 14) / 2.0, 14, 14)];
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        iv.image = [EditorWindowController cachedIconForPath:path];
        [tab addSubview:iv];
        [iv release];

        NSButton *titleBtn = [[NSButton alloc] initWithFrame:NSMakeRect(26, 0, tabWidth - 50, tabHeight)];
        titleBtn.title = name;
        titleBtn.font = [NSFont systemFontOfSize:tabFontSize weight:isActive ? NSFontWeightMedium : NSFontWeightRegular];
        titleBtn.bordered = NO;
        titleBtn.alignment = NSTextAlignmentLeft;
        titleBtn.tag = i;
        titleBtn.target = self;
        titleBtn.action = @selector(tabButtonClicked:);
        titleBtn.contentTintColor = (isActive ? activeTextColor : inactiveTextColor);
        [tab addSubview:titleBtn];
        [titleBtn release];

        NSButton *closeBtn = [[NSButton alloc] initWithFrame:NSMakeRect(tabWidth - 24, (tabHeight - 16) / 2.0, 16, 16)];
        closeBtn.title = @"✕";
        closeBtn.font = [NSFont systemFontOfSize:10 weight:NSFontWeightBold];
        closeBtn.bordered = NO;
        closeBtn.tag = i;
        closeBtn.target = self;
        closeBtn.action = @selector(closeTabButtonClicked:);
        closeBtn.contentTintColor = inactiveTextColor;
        [tab addSubview:closeBtn];
        [closeBtn release];

        [self->_tabBarView addSubview:tab];
        [tab release];

        x += tabWidth;
    }

    CGFloat contentWidth = MAX(barWidth, x);
    self->_tabBarView.frame = NSMakeRect(0, 0, contentWidth, tabHeight);
}

- (void)tabButtonClicked:(NSButton *)sender {
    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < (NSInteger)self->_openTabs.count && idx != self->_activeTabIndex) {
        NSString *path = self->_openTabs[idx];
        if ([self isUntitledTab:path]) {
            [self saveCurrentFile];
            self->_activeTabIndex = idx;
            [self->_currentFilePath release];
            self->_currentFilePath = nil;
            [self renderTabs];
            [self updateStatusInfo];
        } else {
            [self openFile:path];
        }
    }
}

- (void)closeTabButtonClicked:(NSButton *)sender {
    [self closeTabAtIndex:sender.tag];
}

#pragma mark - Detailed Status Bar

- (void)updateStatusInfo {
    if (self->_activeTabIndex < 0 || self->_openTabs.count == 0) {
        self->_statusLabel.stringValue = @"No file open";
        return;
    }

    NSString *text = self->_textView.string ?: @"";
    NSUInteger charCount = text.length;
    NSUInteger lineCount = (charCount == 0) ? 0 : 1;
    NSUInteger wordCount = 0;
    BOOL inWord = NO;

    for (NSUInteger i = 0; i < charCount; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == 10) {
            lineCount++;
            inWord = NO;
        } else if (c == 32 || c == 9 || c == 13) {
            inWord = NO;
        } else if (!inWord) {
            inWord = YES;
            wordCount++;
        }
    }

    NSRange sel = self->_textView.selectedRange;
    NSUInteger cursorLine = 1;
    NSUInteger cursorCol = 1;
    NSUInteger loc = MIN(sel.location, charCount);
    for (NSUInteger i = 0; i < loc; i++) {
        if ([text characterAtIndex:i] == 10) {
            cursorLine++;
            cursorCol = 1;
        } else {
            cursorCol++;
        }
    }

    NSString *selInfo = @"";
    if (sel.length > 0) {
        selInfo = [NSString stringWithFormat:@" (%lu selected)", (unsigned long)sel.length];
    }

    NSString *saveState = self->_currentFilePath ? (self->_saveTimer ? @"● Editing..." : @"✓ Saved") : @"● Untitled";

    self->_statusLabel.stringValue = [NSString stringWithFormat:
        @"Ln %lu, Col %lu%@   |   %lu lines, %lu words, %lu chars   |   UTF-8   |   %@",
        (unsigned long)cursorLine, (unsigned long)cursorCol, selInfo,
        (unsigned long)lineCount, (unsigned long)wordCount, (unsigned long)charCount,
        saveState];
}

- (void)textViewDidChangeSelection:(NSNotification *)notification {
    [self updateStatusInfo];
}

- (void)openFile:(NSString *)filePath {
    if (!filePath || filePath.length == 0) return;

    [self saveCurrentFile];

    if (self->_welcomeView) {
        [self->_welcomeView removeFromSuperview];
        self->_welcomeView = nil;
    }
    self->_textScroll.hidden = NO;
    self->_tabBarContainer.hidden = NO;

    NSUInteger existingIdx = [self->_openTabs indexOfObject:filePath];
    if (existingIdx != NSNotFound) {
        self->_activeTabIndex = existingIdx;
    } else {
        [self->_openTabs addObject:filePath];
        self->_activeTabIndex = self->_openTabs.count - 1;
    }

    if (self->_currentFilePath != filePath) {
        [self->_currentFilePath release];
        self->_currentFilePath = [filePath copy];
    }

    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&err];
    if (!err) {
        self->_textView.string = content ?: @"";
        self->_textView.font = self->_editorFont;
        [self applyLineSpacing];
        [self applyWordWrap];

        [self->_textView setSelectedRange:NSMakeRange(0, 0)];
        [self->_textView scrollPoint:NSMakePoint(0, 0)];

        MPLog(@"Opened file: %@", filePath);
    } else {
        MPLog(@"Failed to read file %@: %@", filePath, err.localizedDescription);
    }

    [self renderTabs];
    [self updateStatusInfo];
}

#pragma mark - New File / Folder

- (NSString *)selectedTargetDirectory {
    NSInteger row = [self->_outlineView selectedRow];
    if (row >= 0) {
        FileNode *node = [self->_outlineView itemAtRow:row];
        if (node && node->_path) {
            return node->_isDir ? node->_path : [node->_path stringByDeletingLastPathComponent];
        }
    }
    return self->_rootPath ?: NSHomeDirectory();
}

- (void)createNewFile {
    NSString *targetDir = [self selectedTargetDirectory];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"New File";
    alert.informativeText = [NSString stringWithFormat:@"Inside: %@", [targetDir lastPathComponent]];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.placeholderString = @"e.g. script.js or notes.txt";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length > 0) {
            NSString *newPath = [targetDir stringByAppendingPathComponent:name];
            NSError *err = nil;
            BOOL success = [@"" writeToFile:newPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
            if (!success || err) {
                NSAlert *errAlert = [NSAlert new];
                errAlert.messageText = @"Failed to Create File";
                errAlert.informativeText = err.localizedDescription ?: @"Could not create file.";
                [errAlert runModal];
            } else {
                [self openFolderAtPath:self->_rootPath];
                [self openFile:newPath];
            }
        }
    }
}

- (void)createNewFolder {
    NSString *targetDir = [self selectedTargetDirectory];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"New Folder";
    alert.informativeText = [NSString stringWithFormat:@"Inside: %@", [targetDir lastPathComponent]];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.placeholderString = @"folder name";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length > 0) {
            NSString *newPath = [targetDir stringByAppendingPathComponent:name];
            NSError *err = nil;
            BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:&err];
            if (!success || err) {
                NSAlert *errAlert = [NSAlert new];
                errAlert.messageText = @"Failed to Create Folder";
                errAlert.informativeText = err.localizedDescription ?: @"Could not create folder.";
                [errAlert runModal];
            } else {
                [self openFolderAtPath:self->_rootPath];
            }
        }
    }
}

#pragma mark - OutlineView Data Source & Delegate

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    FileNode *node = item ? (FileNode *)item : self->_rootNode;
    if (!node) return 0;
    [node loadChildrenIfNeeded];
    return node->_children ? node->_children.count : 0;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(id)item {
    FileNode *node = item ? (FileNode *)item : self->_rootNode;
    if (!node) return nil;
    [node loadChildrenIfNeeded];
    if (!node->_children || idx < 0 || idx >= (NSInteger)node->_children.count) return nil;
    return node->_children[idx];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    if (!item) return NO;
    return ((FileNode *)item)->_isDir;
}

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item {
    FileNode *node = (FileNode *)item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"Cell" owner:self];
    CGFloat rHeight = round(24.0 * self->_uiScale);
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, col.width, rHeight)];
        cell.identifier = @"Cell";

        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(2, (rHeight - 16) / 2.0, 16, 16)];
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        cell.imageView = iv;
        [cell addSubview:iv];

        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.frame = NSMakeRect(22, 2, col.width - 26, rHeight - 4);
        tf.autoresizingMask = NSViewWidthSizable;
        cell.textField = tf;
        [cell addSubview:tf];
    }
    if (node) {
        cell.textField.stringValue = node->_name ?: @"";
        cell.imageView.image = [EditorWindowController cachedIconForNode:node];
    }
    cell.textField.font = [NSFont systemFontOfSize:round(12.5 * self->_uiScale)];
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [self->_outlineView selectedRow];
    if (row < 0) return;
    FileNode *node = [self->_outlineView itemAtRow:row];
    if (node && !node->_isDir) {
        [self openFile:node->_path];
    }
}

@end
