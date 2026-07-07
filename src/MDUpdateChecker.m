#import "MDUpdateChecker.h"

static NSString * const kLatestReleaseURL =
    @"https://api.github.com/repos/maz0/MarkdownEditor/releases/latest";
static NSString * const kReleasesPageURL =
    @"https://github.com/maz0/MarkdownEditor/releases";
static NSString * const kLastCheckKey      = @"lastUpdateCheck";
static NSString * const kSkippedVersionKey = @"skippedVersion";
static const NSTimeInterval kCheckInterval = 60 * 60 * 24; // once a day

@implementation MDUpdateChecker

// ─── Version comparison ──────────────────────────────────────────────────────

+ (NSComparisonResult)compareVersion:(NSString *)a toVersion:(NSString *)b {
    NSArray<NSString *> *pa = [a componentsSeparatedByString:@"."];
    NSArray<NSString *> *pb = [b componentsSeparatedByString:@"."];
    NSUInteger n = MAX(pa.count, pb.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSInteger va = i < pa.count ? pa[i].integerValue : 0;
        NSInteger vb = i < pb.count ? pb[i].integerValue : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

// ─── Public entry points ─────────────────────────────────────────────────────

- (void)checkAutomatically {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDate *last = [ud objectForKey:kLastCheckKey];
    if (last && [NSDate.date timeIntervalSinceDate:last] < kCheckInterval) return;
    [ud setObject:NSDate.date forKey:kLastCheckKey];
    [self fetchLatestReleaseReportingErrors:NO];
}

- (void)checkForUpdates:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:NSDate.date forKey:kLastCheckKey];
    [self fetchLatestReleaseReportingErrors:YES];
}

// ─── Fetch & respond ─────────────────────────────────────────────────────────

- (void)fetchLatestReleaseReportingErrors:(BOOL)report {
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:kLatestReleaseURL]];
    [req setValue:@"MarkdownEditor" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    req.timeoutInterval = 15;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                if (report) [self showError:err.localizedDescription ?: @"No response."];
                return;
            }
            if (status == 404) { // no releases published yet
                if (report) [self showUpToDate];
                return;
            }
            if (status != 200) {
                if (report) [self showError:[NSString
                    stringWithFormat:@"GitHub returned HTTP %ld.", (long)status]];
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0 error:nil];
            if (![json isKindOfClass:NSDictionary.class]) {
                if (report) [self showError:@"Unexpected response from GitHub."];
                return;
            }
            [self handleRelease:json reportingErrors:report];
        });
    }] resume];
}

- (void)handleRelease:(NSDictionary *)json reportingErrors:(BOOL)report {
    NSString *tag = json[@"tag_name"];
    if (![tag isKindOfClass:NSString.class] || tag.length == 0) {
        if (report) [self showError:@"Release has no version tag."];
        return;
    }
    NSString *latest = [tag hasPrefix:@"v"] || [tag hasPrefix:@"V"]
        ? [tag substringFromIndex:1] : tag;
    NSString *current = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";

    if ([MDUpdateChecker compareVersion:current toVersion:latest] != NSOrderedAscending) {
        if (report) [self showUpToDate];
        return;
    }
    // Automatic checks respect a user's "Skip This Version"; manual ones don't.
    NSString *skipped = [[NSUserDefaults standardUserDefaults]
                         stringForKey:kSkippedVersionKey];
    if (!report && [skipped isEqualToString:latest]) return;

    NSString *page = [json[@"html_url"] isKindOfClass:NSString.class]
        ? json[@"html_url"] : kReleasesPageURL;

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Update Available";
    alert.informativeText = [NSString stringWithFormat:
        @"Markdown Editor %@ is available — you have %@.", latest, current];
    [alert addButtonWithTitle:@"View Release"];
    [alert addButtonWithTitle:@"Later"];
    [alert addButtonWithTitle:@"Skip This Version"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:page]];
    } else if (r == NSAlertThirdButtonReturn) {
        [[NSUserDefaults standardUserDefaults] setObject:latest
                                                  forKey:kSkippedVersionKey];
    }
}

// ─── Result alerts (manual check only) ───────────────────────────────────────

- (void)showUpToDate {
    NSString *current = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"You're up to date";
    alert.informativeText = [NSString stringWithFormat:
        @"Markdown Editor %@ is the latest version.", current];
    [alert runModal];
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Could not check for updates";
    alert.informativeText = message ?: @"Unknown error.";
    [alert runModal];
}

@end
