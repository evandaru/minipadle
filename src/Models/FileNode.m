#import "FileNode.h"

@implementation FileNode

- (instancetype)initWithPath:(NSString *)path isDir:(BOOL)isDir showHidden:(BOOL)showHidden {
    if ((self = [super init])) {
        self->_path = [path copy];
        self->_name = [[path lastPathComponent] copy];
        self->_isDir = isDir;
        self->_showHidden = showHidden;
        self->_childrenLoaded = NO;
        self->_children = isDir ? [NSMutableArray new] : nil;
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)path isDir:(BOOL)isDir {
    return [self initWithPath:path isDir:isDir showHidden:NO];
}

- (void)dealloc {
    [self->_path release];
    [self->_name release];
    [self->_children release];
    [super dealloc];
}

- (void)loadChildrenIfNeeded {
    if (!self->_isDir || self->_childrenLoaded) return;
    self->_childrenLoaded = YES;

    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self->_path error:nil];
    contents = [contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

    for (NSString *sub in contents) {
        if (!self->_showHidden && [sub hasPrefix:@"."]) continue;
        if ([sub isEqualToString:@"node_modules"]) continue;

        NSString *subPath = [self->_path stringByAppendingPathComponent:sub];
        BOOL subIsDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:subPath isDirectory:&subIsDir]) {
            FileNode *child = [[FileNode alloc] initWithPath:subPath isDir:subIsDir showHidden:self->_showHidden];
            [self->_children addObject:child];
            [child release];
        }
    }

    [self->_children sortUsingComparator:^NSComparisonResult(FileNode *a, FileNode *b) {
        if (a->_isDir != b->_isDir) return a->_isDir ? NSOrderedAscending : NSOrderedDescending;
        return [a->_name localizedStandardCompare:b->_name];
    }];
}

- (void)reloadChildren {
    if (!self->_isDir) return;
    [self->_children removeAllObjects];
    self->_childrenLoaded = NO;
    [self loadChildrenIfNeeded];
}

- (void)updateShowHiddenRecursively:(BOOL)showHidden {
    self->_showHidden = showHidden;
    if (self->_childrenLoaded) {
        [self reloadChildren];
        for (FileNode *child in self->_children) {
            if (child->_isDir) {
                [child updateShowHiddenRecursively:showHidden];
            }
        }
    }
}

@end
