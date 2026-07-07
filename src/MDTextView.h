#import <Cocoa/Cocoa.h>

@protocol MDTextViewDropDelegate <NSObject>
// Return the markdown to insert for a dropped image file (or nil to ignore it).
- (NSString *)markdownForDroppedImageAtURL:(NSURL *)url;
@end

// NSTextView that turns dropped image files into markdown image links
// instead of inserting the bare file path.
@interface MDTextView : NSTextView
@property (weak) id<MDTextViewDropDelegate> dropDelegate;
@end
