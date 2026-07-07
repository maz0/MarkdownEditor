#import <Foundation/Foundation.h>

// User templates: plain .md files in Application Support, surfaced in the
// slash menu. {{cursor}} marks where the caret lands; {{date}}, {{time}},
// {{weekday}} and {{filename}} are substituted at insertion time.
@interface MDTemplates : NSObject
+ (NSURL *)folderURL;                    // creates the folder if missing
+ (void)ensureSeeded;                    // writes the starter templates once
+ (NSArray<NSDictionary *> *)load;       // @{ @"name", @"content" } per file
+ (NSString *)substituteVariables:(NSString *)s filename:(NSString *)filename;
@end
