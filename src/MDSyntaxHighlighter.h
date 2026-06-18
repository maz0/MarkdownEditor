#import <Cocoa/Cocoa.h>

@interface MDSyntaxHighlighter : NSObject
- (void)highlight:(NSTextStorage *)ts font:(NSFont *)font;
@end
