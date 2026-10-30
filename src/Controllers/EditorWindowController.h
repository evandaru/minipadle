#import "FileNode.h"
#import "QuickOpenWindowController.h"
#import <Cocoa/Cocoa.h>

@interface EditorWindowController
    : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate,
                          NSTextViewDelegate, QuickOpenDelegate,
                          NSSplitViewDelegate, NSMenuDelegate> {
@public
  NSString *_rootPath;
  NSString *_currentFilePath;
  FileNode *_rootNode;

  NSSplitView *_splitView;
  NSOutlineView *_outlineView;
  NSScrollView *_textScroll;
  NSTextView *_textView;
  NSTextField *_statusLabel;
  NSTimer *_saveTimer;
  NSFont *_editorFont;
  CGFloat _fontSize;
  NSString *_fontName;
  CGFloat _lineSpacing;
  CGFloat _uiScale;
  BOOL _wordWrapEnabled;
  BOOL _isDarkMode;
  BOOL _autosaveEnabled;
  BOOL _showHiddenFiles;

  CGFloat _lastSidebarWidth;

  // Clipboard
  NSString *_clipboardPath;
  BOOL _isCutOperation;

  // Quick Open Controller
  QuickOpenWindowController *_quickOpenController;

  // Tab Management
  NSMutableArray<NSString *> *_openTabs;
  NSInteger _activeTabIndex;
  NSScrollView *_tabScrollView;
  NSView *_tabBarView;
  NSView *_tabBarContainer;
  NSButton *_mainMenuBtn;

  // Obsidian style Welcome & Empty Views
  NSView *_welcomeView;
  NSView *_sidebarEmptyView;
  NSView *_leftContainer;
  NSView *_rightContainer;
}

- (void)openFolderDialog;
- (void)openFolderAtPath:(NSString *)path;
- (void)openFile:(NSString *)filePath;
- (void)newUntitledNote;
- (void)saveCurrentFile;
- (void)saveCurrentFileAs;
- (void)createNewFile;
- (void)createNewFolder;
- (void)closeActiveTab;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)applyWordWrap;
- (void)applyLineSpacing;
- (void)toggleShowHiddenFiles;
- (void)toggleSidebar;
- (void)goToMainMenu;

// File Manager Actions
- (void)renameSelectedItem;
- (void)deleteSelectedItem;
- (void)copySelectedItem;
- (void)cutSelectedItem;
- (void)pasteIntoSelectedItem;
- (void)copyPathSelectedItem;
- (void)revealSelectedItemInFinder;

// Search & Zoom
- (void)showQuickOpen;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;

// Settings
- (void)openSettings;

@end
