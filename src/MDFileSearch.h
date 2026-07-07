#import <Cocoa/Cocoa.h>

// Find in Folder: searches markdown/text files in the frontmost document's
// folder (or a picked one) and jumps to matches.
@interface MDFileSearch : NSObject
- (void)show;
@end
