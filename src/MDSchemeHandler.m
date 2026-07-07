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
    NSURLResponse *resp = [[NSURLResponse alloc] initWithURL:task.request.URL
                                                    MIMEType:mime
                                       expectedContentLength:(NSInteger)data.length
                                            textEncodingName:nil];
    [task didReceiveResponse:resp];
    [task didReceiveData:data];
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
        };
    });
    return map[ext];
}

@end
