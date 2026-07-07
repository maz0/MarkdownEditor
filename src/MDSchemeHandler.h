#import <WebKit/WebKit.h>

// Serves local image files to the preview under the mdpreview:// scheme.
// WKWebView refuses file:// subresources for loadHTMLString: content; routing
// through a custom scheme is the sanctioned way to show images beside the doc.
@interface MDSchemeHandler : NSObject <WKURLSchemeHandler>
@end
