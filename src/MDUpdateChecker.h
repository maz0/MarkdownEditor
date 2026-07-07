#import <Cocoa/Cocoa.h>

@interface MDUpdateChecker : NSObject
- (void)checkAutomatically;          // throttled to once/day, silent unless update found
- (void)checkForUpdates:(id)sender;  // manual menu action, always reports a result
+ (NSComparisonResult)compareVersion:(NSString *)a toVersion:(NSString *)b;
@end
