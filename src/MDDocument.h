#import <Cocoa/Cocoa.h>

@interface MDDocument : NSDocument <NSTextViewDelegate, NSToolbarDelegate, NSTextFieldDelegate>
// Move the caret to a range (e.g. a search match) and reveal it.
- (void)jumpToCharacterRange:(NSRange)range;
@end
