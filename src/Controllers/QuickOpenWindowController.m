#import "QuickOpenWindowController.h"

@interface QuickOpenWindowController () {
    NSString *_rootPath;
    NSMutableArray<NSString *> *_allFiles;
    NSMutableArray<NSString *> *_filteredFiles;
    NSMutableDictionary<NSString *, NSImage *> *_iconCache;
    NSVisualEffectView *_vfx;
    NSSearchField *_searchField;
    NSTableView *_tableView;
    BOOL _isIndexing;
}
@end

@implementation QuickOpenWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 580, 390);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Quick Open";
    panel.titleVisibility = NSWindowTitleHidden;
    panel.titlebarAppearsTransparent = YES;
    panel.floatingPanel = YES;
    panel.hidesOnDeactivate = NO;
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    panel.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;

    // Hide default window traffic light buttons completely
    [[panel standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[panel standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[panel standardWindowButton:NSWindowZoomButton] setHidden:YES];

    if ((self = [super initWithWindow:panel])) {
        self->_allFiles = [NSMutableArray new];
        self->_filteredFiles = [NSMutableArray new];
        self->_iconCache = [NSMutableDictionary new];

        panel.delegate = self;

        // Frosted Glass Background
        self->_vfx = [[NSVisualEffectView alloc] initWithFrame:frame];
        self->_vfx.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        self->_vfx.state = NSVisualEffectStateActive;
        self->_vfx.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self->_vfx.wantsLayer = YES;
        self->_vfx.layer.cornerRadius = 14.0;
        self->_vfx.layer.masksToBounds = YES;
        self->_vfx.layer.borderWidth = 1.0;

        // Sleek Search Field
        self->_searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(14, 338, 552, 38)];
        self->_searchField.placeholderString = @"Search files by name (⌘P)...";
        self->_searchField.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
        self->_searchField.focusRingType = NSFocusRingTypeNone;
        self->_searchField.delegate = self;
        self->_searchField.target = self;
        self->_searchField.action = @selector(searchQueryChanged:);
        self->_searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [self->_vfx addSubview:self->_searchField];

        // Results Table View
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, 14, 552, 312)];
        scroll.hasVerticalScroller = YES;
        scroll.hasHorizontalScroller = NO;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scroll.drawsBackground = NO;

        self->_tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
        self->_tableView.headerView = nil;
        self->_tableView.rowHeight = 32;
        self->_tableView.backgroundColor = [NSColor clearColor];
        self->_tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
        self->_tableView.dataSource = self;
        self->_tableView.delegate = self;
        self->_tableView.target = self;
        self->_tableView.doubleAction = @selector(rowDoubleClicked:);

        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ResultCol"];
        col.width = 544;
        [self->_tableView addTableColumn:col];
        scroll.documentView = self->_tableView;
        [self->_vfx addSubview:scroll];

        panel.contentView = self->_vfx;
    }
    return self;
}

- (void)dealloc {
    [_rootPath release];
    [_allFiles release];
    [_filteredFiles release];
    [_iconCache release];
    [super dealloc];
}

#pragma mark - Theme & Appearance

- (void)applyTheme:(BOOL)isDark {
    self.window.appearance = isDark ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
                                    : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self->_vfx.material = isDark ? NSVisualEffectMaterialHUDWindow : NSVisualEffectMaterialPopover;
    self->_vfx.layer.borderColor = (isDark ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.15]
                                           : [NSColor colorWithCalibratedWhite:0.0 alpha:0.12]).CGColor;
}

#pragma mark - On-Demand File Indexing

- (void)preloadRootPath:(NSString *)rootPath {
    if (!rootPath || [rootPath isEqualToString:self->_rootPath]) return;
    [self->_rootPath release];
    self->_rootPath = [rootPath copy];
    [self->_allFiles removeAllObjects];
}

- (void)collectFilesRecursively:(NSString *)dir into:(NSMutableArray *)list maxDepth:(int)depth {
    if (depth <= 0 || list.count >= 2000) return;

    @autoreleasepool {
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        if (!contents) return;

        for (NSString *sub in contents) {
            if (list.count >= 2000) break;

            if ([sub hasPrefix:@"."] ||
                [sub isEqualToString:@"node_modules"] ||
                [sub isEqualToString:@"build"] ||
                [sub isEqualToString:@"dist"] ||
                [sub isEqualToString:@"target"] ||
                [sub isEqualToString:@"bin"] ||
                [sub isEqualToString:@"obj"] ||
                [sub isEqualToString:@"Pods"] ||
                [sub isEqualToString:@"DerivedData"] ||
                [sub isEqualToString:@"vendor"] ||
                [sub isEqualToString:@"__pycache__"] ||
                [sub hasSuffix:@".app"] ||
                [sub hasSuffix:@".framework"] ||
                [sub hasSuffix:@".xcodeproj"] ||
                [sub hasSuffix:@".xcworkspace"] ||
                [sub hasSuffix:@".dSYM"]) {
                continue;
            }

            NSString *full = [dir stringByAppendingPathComponent:sub];
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir]) {
                if (isDir) {
                    [self collectFilesRecursively:full into:list maxDepth:depth - 1];
                } else {
                    [list addObject:full];
                }
            }
        }
    }
}

- (void)indexRootPathInBackground:(NSString *)rootPath {
    if (self->_isIndexing || !rootPath) return;
    self->_isIndexing = YES;

    NSString *targetPath = [rootPath copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *temp = [NSMutableArray arrayWithCapacity:500];
        [self collectFilesRecursively:targetPath into:temp maxDepth:6];

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_isIndexing = NO;
            if ([self->_rootPath isEqualToString:targetPath]) {
                [self->_allFiles setArray:temp];
                [self filterResults];
            }
            [targetPath release];
        });
    });
}

#pragma mark - Presentation

- (void)presentWithRootPath:(NSString *)rootPath {
    BOOL isDark = YES;
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MiniPadleDarkMode"]) {
        isDark = [[NSUserDefaults standardUserDefaults] boolForKey:@"MiniPadleDarkMode"];
    }
    [self presentWithRootPath:rootPath isDarkMode:isDark];
}

- (void)presentWithRootPath:(NSString *)rootPath isDarkMode:(BOOL)isDark {
    [self applyTheme:isDark];
    self->_searchField.stringValue = @"";

    BOOL pathChanged = (!self->_rootPath || ![self->_rootPath isEqualToString:rootPath]);
    if (pathChanged) {
        [self->_rootPath release];
        self->_rootPath = [rootPath copy];
        [self->_allFiles removeAllObjects];
    }

    if (self->_allFiles.count == 0 && rootPath) {
        [self indexRootPathInBackground:rootPath];
    } else {
        [self filterResults];
    }

    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    NSRect r = self.window.frame;
    CGFloat y = screen.origin.y + (screen.size.height - r.size.height) * 0.72;
    [self.window setFrameOrigin:NSMakePoint(screen.origin.x + (screen.size.width - r.size.width) / 2.0, y)];

    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self->_searchField];
}

#pragma mark - Search & Filtering

- (void)filterResults {
    [self->_filteredFiles removeAllObjects];
    NSString *raw = self->_searchField.stringValue;
    NSString *query = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;

    if (query.length == 0) {
        NSInteger maxShow = MIN((NSInteger)self->_allFiles.count, 100);
        for (NSInteger i = 0; i < maxShow; i++) {
            [self->_filteredFiles addObject:self->_allFiles[i]];
        }
    } else {
        for (NSString *path in self->_allFiles) {
            NSString *name = [path lastPathComponent].lowercaseString;
            if ([name containsString:query] || [path.lowercaseString containsString:query]) {
                [self->_filteredFiles addObject:path];
                if (self->_filteredFiles.count >= 100) break;
            }
        }
    }

    [self->_tableView reloadData];
    if (self->_filteredFiles.count > 0) {
        [self->_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

- (void)searchQueryChanged:(id)sender {
    [self filterResults];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [self filterResults];
}

#pragma mark - Keyboard Navigation & Selection

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(moveDown:)) {
        NSInteger next = self->_tableView.selectedRow + 1;
        if (next < (NSInteger)self->_filteredFiles.count) {
            [self->_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
            [self->_tableView scrollRowToVisible:next];
        }
        return YES;
    } else if (commandSelector == @selector(moveUp:)) {
        NSInteger prev = self->_tableView.selectedRow - 1;
        if (prev >= 0) {
            [self->_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:prev] byExtendingSelection:NO];
            [self->_tableView scrollRowToVisible:prev];
        }
        return YES;
    } else if (commandSelector == @selector(insertNewline:)) {
        [self selectCurrent];
        return YES;
    } else if (commandSelector == @selector(cancelOperation:)) {
        [self close];
        return YES;
    }
    return NO;
}

- (void)rowDoubleClicked:(id)sender {
    [self selectCurrent];
}

- (void)selectCurrent {
    NSInteger row = self->_tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)self->_filteredFiles.count) {
        NSString *chosen = self->_filteredFiles[row];
        [self close];
        if ([self.delegate respondsToSelector:@selector(quickOpenDidSelectFilePath:)]) {
            [self.delegate quickOpenDidSelectFilePath:chosen];
        }
    }
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self close];
}

#pragma mark - Cached Icons

- (NSImage *)iconForPath:(NSString *)path {
    NSString *ext = [path pathExtension].lowercaseString;
    if (ext.length == 0) ext = @"__none__";

    NSImage *img = [self->_iconCache objectForKey:ext];
    if (!img) {
        img = [[NSWorkspace sharedWorkspace] iconForFileType:ext];
        if (!img) {
            img = [[NSWorkspace sharedWorkspace] iconForFile:path];
        }
        if (img) {
            img.size = NSMakeSize(18, 18);
            if (self->_iconCache.count < 50) {
                [self->_iconCache setObject:img forKey:ext];
            }
        }
    }
    return img;
}

#pragma mark - TableView Delegate & DataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self->_filteredFiles.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row >= (NSInteger)self->_filteredFiles.count) return nil;
    NSString *full = self->_filteredFiles[row];

    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"QuickCell" owner:self];
    if (!cell) {
        cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 32)] autorelease];
        cell.identifier = @"QuickCell";

        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 6, 20, 20)];
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        cell.imageView = iv;
        [cell addSubview:iv];
        [iv release];

        NSTextField *nameLabel = [NSTextField labelWithString:@""];
        nameLabel.frame = NSMakeRect(34, 6, 210, 20);
        nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        nameLabel.textColor = [NSColor labelColor];
        nameLabel.backgroundColor = [NSColor clearColor];
        nameLabel.bordered = NO;
        nameLabel.identifier = @"Name";
        [cell addSubview:nameLabel];

        NSTextField *pathLabel = [NSTextField labelWithString:@""];
        pathLabel.frame = NSMakeRect(250, 6, tableColumn.width - 258, 20);
        pathLabel.font = [NSFont systemFontOfSize:11];
        pathLabel.textColor = [NSColor secondaryLabelColor];
        pathLabel.backgroundColor = [NSColor clearColor];
        pathLabel.bordered = NO;
        pathLabel.identifier = @"Path";
        pathLabel.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:pathLabel];
    }

    cell.imageView.image = [self iconForPath:full];

    for (NSView *sub in cell.subviews) {
        if ([sub isKindOfClass:[NSTextField class]]) {
            NSTextField *tf = (NSTextField *)sub;
            if ([tf.identifier isEqualToString:@"Name"]) {
                tf.stringValue = [full lastPathComponent];
            } else if ([tf.identifier isEqualToString:@"Path"]) {
                NSString *rel = full;
                if (self->_rootPath && [full hasPrefix:self->_rootPath]) {
                    rel = [full substringFromIndex:self->_rootPath.length];
                    if ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
                }
                tf.stringValue = rel;
            }
        }
    }
    return cell;
}

@end
