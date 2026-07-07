#import "MDTextView.h"

@implementation MDTextView

static BOOL isImageURL(NSURL *url) {
    static NSSet<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"gif", @"svg",
                                     @"webp", @"bmp", @"tiff", @"tif", @"heic"]];
    });
    return [exts containsObject:url.pathExtension.lowercaseString];
}

- (NSArray<NSURL *> *)imageURLsFromDraggingInfo:(id<NSDraggingInfo>)info {
    NSArray<NSURL *> *urls = [info.draggingPasteboard
        readObjectsForClasses:@[NSURL.class]
                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray<NSURL *> *images = [NSMutableArray new];
    for (NSURL *u in urls)
        if (isImageURL(u)) [images addObject:u];
    return images;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *images = [self imageURLsFromDraggingInfo:sender];
    if (!images.count || !self.dropDelegate)
        return [super performDragOperation:sender];

    NSMutableArray<NSString *> *snippets = [NSMutableArray new];
    for (NSURL *u in images) {
        NSString *md = [self.dropDelegate markdownForDroppedImageAtURL:u];
        if (md) [snippets addObject:md];
    }
    if (!snippets.count) return [super performDragOperation:sender];

    NSPoint pt = [self convertPoint:sender.draggingLocation fromView:nil];
    NSUInteger idx = [self characterIndexForInsertionAtPoint:pt];
    NSRange ins = NSMakeRange(MIN(idx, self.string.length), 0);
    NSString *text = [snippets componentsJoinedByString:@"\n"];
    if ([self shouldChangeTextInRange:ins replacementString:text]) {
        [self replaceCharactersInRange:ins withString:text];
        [self didChangeText];
        [self setSelectedRange:NSMakeRange(ins.location + text.length, 0)];
    }
    return YES;
}

@end
