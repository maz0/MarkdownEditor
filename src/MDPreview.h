#import <Foundation/Foundation.h>

@interface MDPreview : NSObject
// Static, self-contained document (export, tests). Engines inlined only if used.
+ (NSString *)htmlFromMarkdown:(NSString *)markdown;
// Live preview: persistent shell page loaded once…
+ (NSString *)shellHTML;
// …then updated incrementally with body HTML via window.mdUpdate(html, base).
+ (NSString *)bodyFromMarkdown:(NSString *)markdown;
// Escape a string for embedding as a JS string literal in evaluateJavaScript.
+ (NSString *)jsStringLiteral:(NSString *)s;
@end
