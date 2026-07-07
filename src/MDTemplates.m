#import "MDTemplates.h"

@implementation MDTemplates

+ (NSURL *)folderURL {
    NSURL *appSupport = [[NSFileManager.defaultManager
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask] firstObject];
    NSURL *dir = [[appSupport URLByAppendingPathComponent:@"MarkdownEditor"]
                  URLByAppendingPathComponent:@"Templates"];
    [NSFileManager.defaultManager createDirectoryAtURL:dir
                           withIntermediateDirectories:YES
                                            attributes:nil error:nil];
    return dir;
}

// Starters are real files so the user can edit or delete them; the flag keeps
// deleted ones from resurrecting on the next launch.
+ (void)ensureSeeded {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:@"templatesSeeded"]) return;
    [ud setBool:YES forKey:@"templatesSeeded"];

    NSDictionary<NSString *, NSString *> *seeds = @{
        @"Meeting note":
            @"# {{cursor}}\n\n"
            @"**Date:** {{weekday}}, {{date}}\n"
            @"**Attendees:** \n\n"
            @"## Notes\n\n"
            @"## Actions\n\n"
            @"- [ ] \n",
        @"Daily note":
            @"# {{date}}\n\n"
            @"## Focus\n\n"
            @"{{cursor}}\n\n"
            @"## Notes\n\n"
            @"## Tomorrow\n\n"
            @"- [ ] \n",
        @"Weekly review":
            @"# Week in review — {{date}}\n\n"
            @"## What went well\n\n"
            @"{{cursor}}\n\n"
            @"## What could be better\n\n"
            @"## Next week\n\n"
            @"- [ ] \n",
    };
    NSURL *dir = [self folderURL];
    [seeds enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *content, BOOL *stop) {
        NSURL *file = [dir URLByAppendingPathComponent:
                       [name stringByAppendingPathExtension:@"md"]];
        if (![file checkResourceIsReachableAndReturnError:nil])
            [content writeToURL:file atomically:YES
                       encoding:NSUTF8StringEncoding error:nil];
    }];
}

+ (NSArray<NSDictionary *> *)load {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager
        contentsOfDirectoryAtURL:[self folderURL]
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:nil];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    for (NSURL *f in [files sortedArrayUsingComparator:^(NSURL *a, NSURL *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }]) {
        if (![f.pathExtension.lowercaseString isEqualToString:@"md"]) continue;
        NSString *content = [NSString stringWithContentsOfURL:f
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
        if (!content) continue;
        [out addObject:@{
            @"name":    [f.lastPathComponent stringByDeletingPathExtension],
            @"content": content,
        }];
    }
    return out;
}

+ (NSString *)substituteVariables:(NSString *)s filename:(NSString *)filename {
    if ([s rangeOfString:@"{{"].location == NSNotFound) return s;
    NSDate *now = [NSDate date];
    NSDateFormatter *fmt = [NSDateFormatter new];

    fmt.dateFormat = @"yyyy-MM-dd";
    s = [s stringByReplacingOccurrencesOfString:@"{{date}}"
                                     withString:[fmt stringFromDate:now]];
    fmt.dateFormat = @"HH:mm";
    s = [s stringByReplacingOccurrencesOfString:@"{{time}}"
                                     withString:[fmt stringFromDate:now]];
    fmt.dateFormat = @"EEEE";
    s = [s stringByReplacingOccurrencesOfString:@"{{weekday}}"
                                     withString:[fmt stringFromDate:now]];
    s = [s stringByReplacingOccurrencesOfString:@"{{filename}}"
                                     withString:filename ?: @""];
    return s;
}

@end
