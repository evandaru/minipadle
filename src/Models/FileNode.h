#import <Foundation/Foundation.h>

@interface FileNode : NSObject {
@public
  NSString *_path;
  NSString *_name;
  BOOL _isDir;
  BOOL _childrenLoaded;
  BOOL _showHidden;
  NSMutableArray<FileNode *> *_children;
}

- (instancetype)initWithPath:(NSString *)path isDir:(BOOL)isDir;
- (instancetype)initWithPath:(NSString *)path
                       isDir:(BOOL)isDir
                  showHidden:(BOOL)showHidden;
- (void)loadChildrenIfNeeded;
- (void)reloadChildren;
- (void)updateShowHiddenRecursively:(BOOL)showHidden;

@end
