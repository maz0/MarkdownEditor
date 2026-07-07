#import "MDSchemeHandler.h"

@implementation MDSchemeHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSString *path = task.request.URL.path;
    NSString *mime = [MDSchemeHandler mimeForExtension:path.pathExtension.lowercaseString];
    NSData   *data = mime ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data) {
        [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorFileDoesNotExist
                                                userInfo:nil]];
        return;
    }

    // WebKit's media loader asks for byte ranges; answer them or video
    // elements refuse to play.
    NSString *range = [task.request valueForHTTPHeaderField:@"Range"];
    NSUInteger total = data.length;
    NSUInteger start = 0, end = total ? total - 1 : 0;
    BOOL partial = NO;
    if ([range hasPrefix:@"bytes="]) {
        NSArray<NSString *> *parts = [[range substringFromIndex:6]
                                      componentsSeparatedByString:@"-"];
        if (parts.count == 2) {
            start = (NSUInteger)MAX(0, parts[0].longLongValue);
            if (parts[1].length) end = (NSUInteger)parts[1].longLongValue;
            if (start < total) {
                end = MIN(end, total - 1);
                partial = YES;
            } else {
                start = 0; // unsatisfiable range: fall back to the full body
            }
        }
    }
    NSData *body = partial
        ? [data subdataWithRange:NSMakeRange(start, end - start + 1)]
        : data;

    NSMutableDictionary *headers = [@{
        @"Content-Type":   mime,
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)body.length],
        @"Accept-Ranges":  @"bytes",
    } mutableCopy];
    if (partial)
        headers[@"Content-Range"] = [NSString stringWithFormat:@"bytes %lu-%lu/%lu",
            (unsigned long)start, (unsigned long)end, (unsigned long)total];

    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc]
        initWithURL:task.request.URL
         statusCode:partial ? 206 : 200
        HTTPVersion:@"HTTP/1.1"
       headerFields:headers];
    [task didReceiveResponse:resp];
    [task didReceiveData:body];
    [task didFinish];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {}

// Images only — the preview has no business serving arbitrary local files.
+ (NSString *)mimeForExtension:(NSString *)ext {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"png":  @"image/png",
            @"jpg":  @"image/jpeg",
            @"jpeg": @"image/jpeg",
            @"gif":  @"image/gif",
            @"svg":  @"image/svg+xml",
            @"webp": @"image/webp",
            @"bmp":  @"image/bmp",
            @"tiff": @"image/tiff",
            @"tif":  @"image/tiff",
            @"heic": @"image/heic",
            @"mp4":  @"video/mp4",
            @"m4v":  @"video/x-m4v",
            @"mov":  @"video/quicktime",
            @"webm": @"video/webm",
        };
    });
    return map[ext];
}

@end
