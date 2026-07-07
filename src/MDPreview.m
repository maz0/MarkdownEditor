#import "MDPreview.h"

@implementation MDPreview

// ─── Static full document (export, tests) ────────────────────────────────────

+ (NSString *)htmlFromMarkdown:(NSString *)md {
    BOOL usedMermaid = NO, usedCode = NO;
    NSString *body = [self bodyFromMarkdown:md usedMermaid:&usedMermaid usedCode:&usedCode];

    // Engines are inlined rather than referenced by URL: WKWebView does not
    // grant loadHTMLString: content read access to file:// subresources, and
    // an exported file must be self-contained anyway.
    NSMutableString *tail = [NSMutableString new];
    if (usedMermaid && [self mermaidEngineSource]) {
        [tail appendFormat:
            @"<script>%@</script>"
            @"<script>mermaid.initialize({startOnLoad:true,securityLevel:'loose',"
            @"theme:matchMedia('(prefers-color-scheme:dark)').matches?'dark':'default'});"
            @"</script>", [self mermaidEngineSource]];
    }
    if (usedCode && [self hljsEngineSource]) {
        [tail appendFormat:@"<script>%@</script><script>hljs.highlightAll();</script>",
            [self hljsEngineSource]];
    }

    return [NSString stringWithFormat:@"<!DOCTYPE html><html><head>"
        @"<meta charset=\"utf-8\">"
        @"<style>%@</style>"
        @"</head><body>%@%@</body></html>",
        [self css], body, tail];
}

// ─── Live preview shell ──────────────────────────────────────────────────────
// Loaded into the WKWebView once; subsequent edits call window.mdUpdate(html,
// base) so the page never navigates — scroll position survives and mermaid/
// highlight re-run only on the fresh nodes.

+ (NSString *)shellHTML {
    NSString *mermaid = [self mermaidEngineSource] ?: @"";
    NSString *hljs    = [self hljsEngineSource] ?: @"";
    return [NSString stringWithFormat:@"<!DOCTYPE html><html><head>"
        @"<meta charset=\"utf-8\">"
        @"<base href=\"\">"
        @"<style>%@</style>"
        @"</head><body><div id=\"content\"></div>"
        @"<script>%@</script>"
        @"<script>%@</script>"
        @"<script>"
        @"var dark=matchMedia('(prefers-color-scheme:dark)');"
        @"function mmInit(){mermaid.initialize({startOnLoad:false,securityLevel:'loose',"
        @"theme:dark.matches?'dark':'default'});}"
        @"mmInit();"
        @"window.__last='';"
        @"window.mdUpdate=function(html,base){"
        @"if(base!=null)document.querySelector('base').href=base;"
        @"window.__last=html;"
        @"document.getElementById('content').innerHTML=html;"
        @"document.querySelectorAll('#content pre code').forEach(function(el){hljs.highlightElement(el);});"
        @"try{mermaid.run({querySelector:'#content .mermaid'});}catch(e){}"
        @"};"
        @"dark.addEventListener('change',function(){mmInit();window.mdUpdate(window.__last);});"
        @"</script></body></html>",
        [self css], mermaid, hljs];
}

+ (NSString *)bodyFromMarkdown:(NSString *)md {
    BOOL m, c;
    return [self bodyFromMarkdown:md usedMermaid:&m usedCode:&c];
}

+ (NSString *)jsStringLiteral:(NSString *)s {
    NSMutableString *r = [s mutableCopy];
    [r replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\n" withString:@"\\n"  options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\r" withString:@"\\r"  options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@" " withString:@"\\u2028" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@" " withString:@"\\u2029" options:0 range:NSMakeRange(0, r.length)];
    return [NSString stringWithFormat:@"\"%@\"", r];
}

// ─── Markdown → body HTML ────────────────────────────────────────────────────

+ (NSString *)bodyFromMarkdown:(NSString *)md
                   usedMermaid:(BOOL *)usedMermaid
                      usedCode:(BOOL *)usedCode {
    *usedMermaid = NO;
    *usedCode    = NO;
    NSMutableString *body = [NSMutableString new];
    NSArray<NSString *> *lines = [md componentsSeparatedByString:@"\n"];

    BOOL inFence   = NO;
    BOOL inMermaid = NO;   // current fence is a ```mermaid block
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
                    *usedMermaid = YES;
                    [body appendString:@"<pre class=\"mermaid\">"];
                } else {
                    *usedCode = YES;
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
                // GFM task list: - [ ] todo / - [x] done
                if ([item hasPrefix:@"[ ] "]) {
                    [body appendFormat:@"<li class=\"task\"><input type=\"checkbox\" disabled> %@</li>\n",
                        [self inline:[item substringFromIndex:4]]];
                } else if ([item hasPrefix:@"[x] "] || [item hasPrefix:@"[X] "]) {
                    [body appendFormat:@"<li class=\"task\"><input type=\"checkbox\" checked disabled> %@</li>\n",
                        [self inline:[item substringFromIndex:4]]];
                } else {
                    [body appendFormat:@"<li>%@</li>\n", [self inline:item]];
                }
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

    return body;
}

// ─── Bundled JS engines ──────────────────────────────────────────────────────
// Bundled mermaid is v10 — v11 needs a newer WebKit than macOS 12 ships.
// Engines ship DEFLATE-compressed (~4:1) and are inflated once on first use;
// a plain .js beside the binary also works (used by test harnesses).

+ (NSString *)engineSourceNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *z = [bundle URLForResource:name withExtension:@"js.z"];
    if (z) {
        NSData *data = [[NSData dataWithContentsOfURL:z]
            decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:nil];
        if (data)
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSURL *plain = [bundle URLForResource:name withExtension:@"js"];
    return plain ? [NSString stringWithContentsOfURL:plain
                                            encoding:NSUTF8StringEncoding
                                               error:nil] : nil;
}

+ (NSString *)mermaidEngineSource {
    static NSString *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [self engineSourceNamed:@"mermaid.min"]; });
    return engine;
}

+ (NSString *)hljsEngineSource {
    static NSString *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [self engineSourceNamed:@"highlight.min"]; });
    return engine;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

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
    @"pre.mermaid{background:none!important;padding:0;text-align:center;overflow:visible}"
    @"li.task{list-style:none;margin-left:-1.3em}"
    @"li.task input{margin-right:.35em;vertical-align:-1px}"
    // highlight.js theme, light (Tomorrow palette)
    @".hljs-comment,.hljs-quote{color:#8e908c;font-style:italic}"
    @".hljs-keyword,.hljs-selector-tag,.hljs-literal{color:#8959a8}"
    @".hljs-string,.hljs-regexp,.hljs-addition{color:#718c00}"
    @".hljs-number,.hljs-attr,.hljs-symbol,.hljs-bullet,.hljs-meta{color:#f5871f}"
    @".hljs-title,.hljs-section,.hljs-name{color:#4271ae}"
    @".hljs-type,.hljs-built_in,.hljs-variable,.hljs-template-variable,.hljs-params{color:#c82829}"
    @".hljs-deletion{color:#c82829}"
    @".hljs-emphasis{font-style:italic}"
    @".hljs-strong{font-weight:700}"
    // Dark overrides last: equal-specificity rules must follow the light ones
    @"@media(prefers-color-scheme:dark){"
    @"body{color:#f0f0f0;background:#1c1c1e}"
    @"pre,code{background:#2c2c2e!important;color:#ff9f0a}"
    @"pre code{color:#e8e8e8}"
    @"a{color:#0a84ff}"
    @"th{background:#2c2c2e}"
    @"td,th{border-color:#3a3a3c}"
    @"tr:nth-child(even){background:#232325}"
    @"blockquote{border-color:#0a84ff;color:#ababab}"
    @"hr{border-color:#3a3a3c}"
    // highlight.js theme, dark (Tomorrow Night palette)
    @".hljs-comment,.hljs-quote{color:#969896}"
    @".hljs-keyword,.hljs-selector-tag,.hljs-literal{color:#b294bb}"
    @".hljs-string,.hljs-regexp,.hljs-addition{color:#b5bd68}"
    @".hljs-number,.hljs-attr,.hljs-symbol,.hljs-bullet,.hljs-meta{color:#de935f}"
    @".hljs-title,.hljs-section,.hljs-name{color:#81a2be}"
    @".hljs-type,.hljs-built_in,.hljs-variable,.hljs-template-variable,.hljs-params{color:#cc6666}"
    @".hljs-deletion{color:#cc6666}"
    @"}";
}

@end
