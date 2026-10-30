#import "AppDelegate.h"
#import "Logger.h"

@interface AppDelegate () {
    NSMenu *_recentMenu;
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
    if (!iconPath || ![[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
        iconPath = @"src/Resources/AppIcon.icns";
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        if (icon) {
            [NSApp setApplicationIconImage:icon];
            [icon release];
        }
    }

    self->_winCtrl = [EditorWindowController new];
    [self setupMenu];
    [self->_winCtrl.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rebuildRecentMenu)
                                                 name:@"MiniPadleRecentFoldersChangedNotification"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setupMenu {
    NSMenu *mainMenu = [NSMenu new];

    // 1. App Menu
    NSMenuItem *appMenuItem = [NSMenuItem new];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"About MiniPadle" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Preferences..." action:@selector(openSettings:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit MiniPadle" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];

    // 2. File Menu
    NSMenuItem *fileItem = [NSMenuItem new];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open Folder..." action:@selector(openFolderDialog) keyEquivalent:@"o"];

    // Recent Folders Submenu
    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    self->_recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    recentItem.submenu = self->_recentMenu;
    [self rebuildRecentMenu];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"New File" action:@selector(createNewFile) keyEquivalent:@"n"];

    NSMenuItem *folderItem = [fileMenu addItemWithTitle:@"New Folder" action:@selector(createNewFolder) keyEquivalent:@"N"];
    folderItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Quick Open..." action:@selector(showQuickOpen) keyEquivalent:@"p"];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save" action:@selector(saveCurrentFile) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeActiveTab:) keyEquivalent:@"w"];
    [fileMenu addItemWithTitle:@"Close Folder (Main Menu)" action:@selector(goToMainMenuAction:) keyEquivalent:@"K"];
    [[fileMenu itemWithTitle:@"Close Folder (Main Menu)"] setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    // 3. Edit Menu
    NSMenuItem *editItem = [NSMenuItem new];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    [editMenu addItem:[NSMenuItem separatorItem]];

    // Find Submenu (⌘F, ⌘G, ⌘⇧G)
    NSMenuItem *findParent = [editMenu addItemWithTitle:@"Find" action:nil keyEquivalent:@""];
    NSMenu *findMenu = [[NSMenu alloc] initWithTitle:@"Find"];

    NSMenuItem *findItem = [findMenu addItemWithTitle:@"Find..." action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
    findItem.tag = NSTextFinderActionShowFindInterface;

    NSMenuItem *findNext = [findMenu addItemWithTitle:@"Find Next" action:@selector(performFindPanelAction:) keyEquivalent:@"g"];
    findNext.tag = NSTextFinderActionNextMatch;

    NSMenuItem *findPrev = [findMenu addItemWithTitle:@"Find Previous" action:@selector(performFindPanelAction:) keyEquivalent:@"G"];
    findPrev.tag = NSTextFinderActionPreviousMatch;

    findParent.submenu = findMenu;
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    // 4. View Menu (Zoom & View controls)
    NSMenuItem *viewItem = [NSMenuItem new];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn) keyEquivalent:@"+"];
    NSMenuItem *zoomInAlt = [viewMenu addItemWithTitle:@"Zoom In (Alt)" action:@selector(zoomIn) keyEquivalent:@"="];
    [zoomInAlt setHidden:YES];

    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"Actual Size" action:@selector(resetZoom) keyEquivalent:@"0"];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    // Toggle Hidden Files (⌘⇧.) ditempatkan dengan benar setelah viewMenu dialokasikan

    NSMenuItem *sideItem = [viewMenu addItemWithTitle:@"Toggle Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@"b"];
    sideItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    
    NSMenuItem *hiddenItem = [viewMenu addItemWithTitle:@"Toggle Hidden Files" action:@selector(toggleShowHiddenFiles:) keyEquivalent:@"."];
    hiddenItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Toggle Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    [[viewMenu itemWithTitle:@"Toggle Full Screen"] setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagControl];

    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    // 5. Help Menu
    NSMenuItem *helpItem = [NSMenuItem new];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpMenu addItemWithTitle:@"Open Log File..." action:@selector(openLogFile:) keyEquivalent:@""];
    helpItem.submenu = helpMenu;
    [mainMenu addItem:helpItem];

    [NSApp setMainMenu:mainMenu];

    
}

- (void)openLogFile:(id)sender {
    [Logger openLogFile];
}

- (void)rebuildRecentMenu {
    if (!self->_recentMenu) return;
    [self->_recentMenu removeAllItems];

    NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:@"MiniPadleRecentFolders"] ?:
                       [[NSUserDefaults standardUserDefaults] arrayForKey:@"MiniCodeRecentFolders"];
    if (recents.count == 0) {
        NSMenuItem *none = [self->_recentMenu addItemWithTitle:@"No Recent Folders" action:nil keyEquivalent:@""];
        [none setEnabled:NO];
        return;
    }

    for (NSString *folder in recents) {
        NSMenuItem *item = [self->_recentMenu addItemWithTitle:[folder lastPathComponent]
                                                        action:@selector(openRecentFolderMenuItem:)
                                                 keyEquivalent:@""];
        item.representedObject = folder;
        item.toolTip = folder;
    }

    [self->_recentMenu addItem:[NSMenuItem separatorItem]];
    [self->_recentMenu addItemWithTitle:@"Clear Recent" action:@selector(clearRecentFolders:) keyEquivalent:@""];
}

- (void)openRecentFolderMenuItem:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    if (path && self->_winCtrl) {
        [self->_winCtrl openFolderAtPath:path];
    }
}

- (void)clearRecentFolders:(id)sender {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MiniPadleRecentFolders"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MiniCodeRecentFolders"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self rebuildRecentMenu];
}

- (void)closeActiveTab:(id)sender {
    if (self->_winCtrl) {
        [self->_winCtrl closeActiveTab];
    }
}

- (void)openSettings:(id)sender {
    if (self->_winCtrl) {
        [self->_winCtrl openSettings];
    }
}

- (void)toggleShowHiddenFiles:(id)sender {
    if (self->_winCtrl) {
        [self->_winCtrl toggleShowHiddenFiles];
    }
}

- (void)toggleSidebar:(id)sender {
    if (self->_winCtrl) {
        [self->_winCtrl toggleSidebar];
    }
}

- (void)goToMainMenuAction:(id)sender {
    if (self->_winCtrl) {
        [self->_winCtrl goToMainMenu];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end
