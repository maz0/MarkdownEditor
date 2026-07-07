#import "MDPreview.h"

@implementation MDPreview

// ─── Public entry point ───────────────────────────────────────────────────────

+ (NSString *)htmlFromMarkdown:(NSString *)md {
    NSMutableString *body = [NSMutableString new];
    NSArray<NSString *> *lines = [md componentsSeparatedByString:@"\n"];

    BOOL inFence   = NO;
    BOOL inMermaid = NO;   // current fence is a ```mermaid block
    BOOL usedMermaid = NO; // at least one mermaid block seen → load engine
    BOOL inUL     = NO;
    BOOL inOL     = NO;
    BOOL inTable  = NO;
    NSMutableArray<NSString *> *para = [NSMutableArray new];

    NSUInteger i = 0;
    while (i < lines.count) {
        NSString *raw = lines[i];
        NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

        // ── Fenced code block ─────────────────────────────────────────
        if ([raw hasPrefix:@"```"] || [raw hasPrefix:@"~~~"]) {
            if (!inFence) {
                [self flushPara:para into:body];
                [self closeLists:&inUL ol:&inOL table:&inTable into:body];
                inFence = YES;
                NSString *lang = [raw substringFromIndex:3];
                lang = [lang stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if ([lang caseInsensitiveCompare:@"mermaid"] == NSOrderedSame) {
                    inMermaid = YES;
                    usedMermaid = YES;
                    [body appendString:@"<pre class=\"mermaid\">"];
                } else {
                    NSString *cls = lang.length ? [NSString stringWithFormat:@" class=\"language-%@\"", [self esc:lang]] : @"";
                    [body appendFormat:@"<pre><code%@>", cls];
                }
            } else {
                [body appendString:inMermaid ? @"</pre>\n" : @"</code></pre>\n"];
                inFence   = NO;
                inMermaid = NO;
            }
            i++; continue;
        }
        if (inFence) {
            [body appendString:[self esc:raw]];
            [body appendString:@"\n"];
            i++; continue;
        }

        // ── Blank line ────────────────────────────────────────────────
        if (trimmed.length == 0) {
            [self flushPara:para into:body];
            [self closeLists:&inUL ol:&inOL table:&inTable into:body];
            i++; continue;
        }

        // ── Heading ───────────────────────────────────────────────────
        NSUInteger h = 0;
        while (h < MIN(6, raw.length) && [raw characterAtIndex:h] == '#') h++;
        if (h > 0 && h < raw.length && [raw characterAtIndex:h] == ' ') {
            [self flushPara:para into:body];
            [self closeLists:&inUL ol:&inOL table:&inTable into:body];
            NSString *text = [raw substringFromIndex:h+1];
            // Generate an id for anchor links
            NSString *anchor = [[text lowercaseString]
                stringByReplacingOccurrencesOfString:@" " withString:@"-"];
            [body appendFormat:@"<h%lu id=\"%@\">%@</h%lu>\n",
                h, [self esc:anchor], [self inline:text], h];
            i++; continue;
        }

        // ── Horizontal rule ───────────────────────────────────────────
        if (trimmed.length >= 3 && ([trimmed hasPrefix:@"---"] || [trimmed hasPrefix:@"***"] || [trimmed hasPrefix:@"___"])) {
            NSCharacterSet *hrChars = [NSCharacterSet characterSetWithCharactersInString:@"-*_ \t"];
            if ([trimmed stringByTrimmingCharactersInSet:hrChars].length == 0) {
                [self flushPara:para into:body];
                [self closeLists:&inUL ol:&inOL table:&inTable into:body];
                [body appendString:@"<hr>\n"];
                i++; continue;
            }
        }

        // ── Blockquote ────────────────────────────────────────────────
        if ([raw hasPrefix:@"> "]) {
            [self flushPara:para into:body];
            [self closeLists:&inUL ol:&inOL table:&inTable into:body];
            NSString *content = [raw substringFromIndex:2];
            [body appendFormat:@"<blockquote><p>%@</p></blockquote>\n", [self inline:content]];
            i++; continue;
        }

        // ── Unordered list ────────────────────────────────────────────
        {
            NSRegularExpression *re = [NSRegularExpression
                regularExpressionWithPattern:@"^(\\s*)[-*+]\\s+(.*)" options:0 error:nil];
            NSTextCheckingResult *m = [re firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
            if (m) {
                [self flushPara:para into:body];
                if (inOL) { [body appendString:@"</ol>\n"]; inOL = NO; }
                if (inTable) { [body appendString:@"</tbody></table>\n"]; inTable = NO; }
                if (!inUL) { [body appendString:@"<ul>\n"]; inUL = YES; }
                NSString *item = [raw substringWithRange:[m rangeAtIndex:2]];
                [body appendFormat:@"<li>%@</li>\n", [self inline:item]];
                i++; continue;
            }
        }

        // ── Ordered list ──────────────────────────────────────────────
        {
            NSRegularExpression *re = [NSRegularExpression
                regularExpressionWithPattern:@"^(\\s*)\\d+\\.\\s+(.*)" options:0 error:nil];
            NSTextCheckingResult *m = [re firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
            if (m) {
                [self flushPara:para into:body];
                if (inUL) { [body appendString:@"</ul>\n"]; inUL = NO; }
                if (inTable) { [body appendString:@"</tbody></table>\n"]; inTable = NO; }
                if (!inOL) { [body appendString:@"<ol>\n"]; inOL = YES; }
                NSString *item = [raw substringWithRange:[m rangeAtIndex:2]];
                [body appendFormat:@"<li>%@</li>\n", [self inline:item]];
                i++; continue;
            }
        }

        // ── Table ─────────────────────────────────────────────────────
        if ([raw hasPrefix:@"|"] && [raw hasSuffix:@"|"]) {
            [self flushPara:para into:body];
            [self closeLists:&inUL ol:&inOL table:nil into:body];
            NSArray<NSString *> *cols = [self tableCells:raw];

            // Peek: is the next line a separator row?
            BOOL isSeparator = NO;
            if (i+1 < lines.count) {
                NSString *next = lines[i+1];
                isSeparator = [next hasPrefix:@"|"] &&
                    [next rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"|-: \t"] invertedSet]].location == NSNotFound;
            }
            if (isSeparator && !inTable) {
                [body appendString:@"<table>\n<thead>\n<tr>"];
                for (NSString *c in cols)
                    [body appendFormat:@"<th>%@</th>", [self inline:c]];
                [body appendString:@"</tr>\n</thead>\n<tbody>\n"];
                inTable = YES;
                i += 2; // skip separator row
                continue;
            } else if (inTable) {
                [body appendString:@"<tr>"];
                for (NSString *c in cols)
                    [body appendFormat:@"<td>%@</td>", [self inline:c]];
                [body appendString:@"</tr>\n"];
                i++; continue;
            }
        }

        // ── Paragraph accumulator ─────────────────────────────────────
        [self closeLists:&inUL ol:&inOL table:&inTable into:body];
        [para addObject:raw];
        i++;
    }

    [self flushPara:para into:body];
    [self closeLists:&inUL ol:&inOL table:&inTable into:body];
    if (inFence) [body appendString:inMermaid ? @"</pre>\n" : @"</code></pre>\n"];

    // Load the mermaid engine only when the document actually uses it.
    // The source is inlined rather than referenced by URL: WKWebView does not
    // grant loadHTMLString: content read access to file:// subresources.
    // Bundled mermaid is v10 — v11 needs a newer WebKit than macOS 12 ships.
    NSString *mermaid = @"";
    if (usedMermaid) {
        NSString *engine = [self mermaidEngineSource];
        if (engine)
            mermaid = [NSString stringWithFormat:
                @"<script>%@</script>"
                @"<script>mermaid.initialize({startOnLoad:true,securityLevel:'loose',"
                @"theme:matchMedia('(prefers-color-scheme:dark)').matches?'dark':'default'});"
                @"</script>", engine];
    }

    return [NSString stringWithFormat:@"<!DOCTYPE html><html><head>"
        @"<meta charset=\"utf-8\">"
        @"<style>%@</style>"
        @"</head><body>%@%@</body></html>",
        [self css], body, mermaid];
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

+ (NSString *)mermaidEngineSource {
    static NSString *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"mermaid.min" withExtension:@"js"];
        if (url)
            engine = [NSString stringWithContentsOfURL:url
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
    });
    return engine;
}

+ (void)flushPara:(NSMutableArray<NSString *> *)lines into:(NSMutableString *)out {
    if (!lines.count) return;
    [out appendFormat:@"<p>%@</p>\n", [self inline:[lines componentsJoinedByString:@" "]]];
    [lines removeAllObjects];
}

+ (void)closeLists:(BOOL *)ul ol:(BOOL *)ol table:(BOOL *)tbl into:(NSMutableString *)out {
    if (ul && *ul) { [out appendString:@"</ul>\n"]; *ul = NO; }
    if (ol && *ol) { [out appendString:@"</ol>\n"]; *ol = NO; }
    if (tbl && *tbl) { [out appendString:@"</tbody></table>\n"]; *tbl = NO; }
}

+ (NSArray<NSString *> *)tableCells:(NSString *)row {
    // Strip leading/trailing |, then split
    NSString *inner = row;
    if ([inner hasPrefix:@"|"]) inner = [inner substringFromIndex:1];
    if ([inner hasSuffix:@"|"]) inner = [inner substringToIndex:inner.length-1];
    NSArray<NSString *> *parts = [inner componentsSeparatedByString:@"|"];
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *p in parts)
        [result addObject:[p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    return result;
}

+ (NSString *)esc:(NSString *)s {
    s = [s stringByReplacingOccurrencesOfString:@"&"  withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<"  withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">"  withString:@"&gt;"];
    s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return s;
}

+ (NSString *)inline:(NSString *)text {
    text = [self esc:text];
    // Images before links
    text = [self re:@"!\\[([^\\]]*?)\\]\\(([^)]*?)\\)"
                rep:@"<img src=\"$2\" alt=\"$1\" style=\"max-width:100%\">"
               into:text];
    // Links
    text = [self re:@"\\[([^\\]]*?)\\]\\(([^)]*?)\\)"
                rep:@"<a href=\"$2\">$1</a>"
               into:text];
    // Bold
    text = [self re:@"\\*\\*([^*]+?)\\*\\*|__([^_]+?)__"
                rep:@"<strong>$1$2</strong>"
               into:text];
    // Italic
    text = [self re:@"(?<!\\*)\\*(?!\\*)([^*\n]+?)(?<!\\*)\\*(?!\\*)"
                rep:@"<em>$1</em>"
               into:text];
    // Inline code
    text = [self re:@"`([^`]+?)`"
                rep:@"<code>$1</code>"
               into:text];
    // Strikethrough
    text = [self re:@"~~([^~]+?)~~"
                rep:@"<del>$1</del>"
               into:text];
    return text;
}

+ (NSString *)re:(NSString *)pat rep:(NSString *)rep into:(NSString *)str {
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:pat options:0 error:nil];
    return [re stringByReplacingMatchesInString:str options:0
                                          range:NSMakeRange(0, str.length)
                                   withTemplate:rep];
}

// ─── CSS ─────────────────────────────────────────────────────────────────────

+ (NSString *)css {
    return
    @"*{box-sizing:border-box}"
    @"body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;"
    @"font-size:15px;line-height:1.75;max-width:740px;margin:0 auto;"
    @"padding:28px 36px 60px;color:#1d1d1f;background:#fff}"
    @"@media(prefers-color-scheme:dark){"
    @"body{color:#f0f0f0;background:#1c1c1e}"
    @"pre,code{background:#2c2c2e!important;color:#ff9f0a}"
    @"a{color:#0a84ff}"
    @"th{background:#2c2c2e}"
    @"td,th{border-color:#3a3a3c}"
    @"blockquote{border-color:#0a84ff;color:#ababab}"
    @"hr{border-color:#3a3a3c}}"
    @"h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.5em 0 .5em;font-weight:600}"
    @"h1{font-size:2em;border-bottom:1px solid #e5e5e5;padding-bottom:.3em}"
    @"h2{font-size:1.5em;border-bottom:1px solid #e5e5e5;padding-bottom:.2em}"
    @"h3{font-size:1.2em}h4{font-size:1em}"
    @"p{margin:.8em 0}"
    @"a{color:#0071e3;text-decoration:none}a:hover{text-decoration:underline}"
    @"code{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.88em;"
    @"background:#f5f5f5;border-radius:4px;padding:2px 5px;color:#c0392b}"
    @"pre{background:#f5f5f5;border-radius:8px;padding:16px;overflow:auto;"
    @"margin:1em 0}"
    @"pre code{background:none;padding:0;color:inherit;font-size:.9em}"
    @"blockquote{border-left:4px solid #0071e3;margin:1em 0;padding:2px 16px;"
    @"color:#666;font-style:italic}"
    @"ul,ol{padding-left:1.8em;margin:.6em 0}"
    @"li{margin:.2em 0}"
    @"table{border-collapse:collapse;width:100%;margin:1em 0}"
    @"th,td{border:1px solid #ddd;padding:8px 12px;text-align:left}"
    @"th{background:#f5f5f5;font-weight:600}"
    @"tr:nth-child(even){background:#fafafa}"
    @"hr{border:none;border-top:1px solid #e5e5e5;margin:1.5em 0}"
    @"img{max-width:100%;border-radius:4px}"
    @"del{color:#888}"
    @"pre.mermaid{background:none!important;padding:0;text-align:center;overflow:visible}";
}

@end
