#import "MDSyntaxHighlighter.h"

// Lazily-initialised regex helpers (one allocation ever)
static NSRegularExpression *rx(NSString *pat) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });
    NSRegularExpression *re = cache[pat];
    if (!re) {
        re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
        cache[pat] = re;
    }
    return re;
}

@implementation MDSyntaxHighlighter

- (void)highlight:(NSTextStorage *)ts font:(NSFont *)font {
    NSString *str = ts.string;
    NSUInteger len = str.length;
    if (len == 0) return;
    // Skip very large documents to keep typing fast
    if (len > 200000) return;

    NSUndoManager *um = ts.layoutManagers.firstObject.firstTextView.undoManager;
    [um disableUndoRegistration];
    [ts beginEditing];

    CGFloat pts = font.pointSize;

    // ── Fonts ─────────────────────────────────────────────────────────
    NSFont *base  = font;
    NSFont *bold  = [NSFont monospacedSystemFontOfSize:pts   weight:NSFontWeightBold];
    NSFont *h1f   = [NSFont monospacedSystemFontOfSize:pts+6 weight:NSFontWeightBold];
    NSFont *h2f   = [NSFont monospacedSystemFontOfSize:pts+4 weight:NSFontWeightSemibold];
    NSFont *h3f   = [NSFont monospacedSystemFontOfSize:pts+2 weight:NSFontWeightMedium];
    NSFont *h4f   = [NSFont monospacedSystemFontOfSize:pts+1 weight:NSFontWeightMedium];

    // ── Colours (all semantic — adapt to dark/light automatically) ────
    NSColor *fg     = NSColor.textColor;
    NSColor *dim    = NSColor.tertiaryLabelColor;
    NSColor *accent = NSColor.systemPurpleColor;
    NSColor *code   = NSColor.systemOrangeColor;
    NSColor *link   = NSColor.systemBlueColor;
    NSColor *quote  = NSColor.systemTealColor;

    // Reset entire document to base style
    [ts setAttributes:@{NSFontAttributeName: base,
                        NSForegroundColorAttributeName: fg}
                range:NSMakeRange(0, len)];

    __block BOOL inFence = NO;

    [str enumerateSubstringsInRange:NSMakeRange(0, len)
                            options:NSStringEnumerationByLines
                         usingBlock:^(NSString *line, NSRange lr, NSRange er, BOOL *stop) {
        if (!line) return;

        // ── Fenced code block ─────────────────────────────────────────
        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
            inFence = !inFence;
            [ts addAttribute:NSForegroundColorAttributeName value:code range:er];
            return;
        }
        if (inFence) {
            [ts addAttribute:NSForegroundColorAttributeName value:code range:er];
            return;
        }

        // ── Headings ──────────────────────────────────────────────────
        NSUInteger h = 0;
        while (h < MIN(6, line.length) && [line characterAtIndex:h] == '#') h++;
        if (h > 0 && h < line.length && [line characterAtIndex:h] == ' ') {
            NSFont *hf = (h==1)?h1f:(h==2)?h2f:(h==3)?h3f:h4f;
            [ts addAttributes:@{NSFontAttributeName: hf,
                                NSForegroundColorAttributeName: accent} range:lr];
            // Dim the "## " marker
            NSUInteger mlen = MIN(h + 1, lr.length);
            [ts addAttribute:NSForegroundColorAttributeName value:dim
                       range:NSMakeRange(lr.location, mlen)];
            return; // no inline parsing inside headings
        }

        // ── Horizontal rule ───────────────────────────────────────────
        if (lr.length >= 3) {
            unichar c = [line characterAtIndex:0];
            if ((c=='-'||c=='*'||c=='_') && [line stringByTrimmingCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"-*_ \t"]].length == 0) {
                [ts addAttribute:NSForegroundColorAttributeName value:dim range:lr];
                return;
            }
        }

        // ── Blockquote ────────────────────────────────────────────────
        if ([line hasPrefix:@"> "]) {
            [ts addAttribute:NSForegroundColorAttributeName value:quote range:lr];
        }

        // ── Inline patterns (applied over whatever block style is set) ─

        // Inline code — do FIRST so bold/italic inside code is not parsed
        [rx(@"`[^`\n]+`") enumerateMatchesInString:str options:0 range:lr
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ts addAttribute:NSForegroundColorAttributeName value:code range:m.range];
        }];

        // Bold **…** or __…__
        [rx(@"\\*\\*[^*\n]+\\*\\*|__[^_\n]+__") enumerateMatchesInString:str options:0 range:lr
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ts addAttribute:NSFontAttributeName value:bold range:m.range];
            [ts addAttribute:NSForegroundColorAttributeName value:dim
                       range:NSMakeRange(m.range.location, 2)];
            [ts addAttribute:NSForegroundColorAttributeName value:dim
                       range:NSMakeRange(NSMaxRange(m.range)-2, 2)];
        }];

        // Italic *…* or _…_ (single, not double)
        [rx(@"(?<!\\*)\\*(?!\\*)[^*\n]+\\*(?!\\*)|(?<!_)_(?!_)[^_\n]+_(?!_)")
            enumerateMatchesInString:str options:0 range:lr
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ts addAttribute:NSObliquenessAttributeName value:@0.2f range:m.range];
            [ts addAttribute:NSForegroundColorAttributeName value:dim
                       range:NSMakeRange(m.range.location, 1)];
            [ts addAttribute:NSForegroundColorAttributeName value:dim
                       range:NSMakeRange(NSMaxRange(m.range)-1, 1)];
        }];

        // Strikethrough ~~…~~
        [rx(@"~~[^~\n]+~~") enumerateMatchesInString:str options:0 range:lr
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ts addAttribute:NSStrikethroughStyleAttributeName
                       value:@(NSUnderlineStyleSingle) range:m.range];
            [ts addAttribute:NSForegroundColorAttributeName value:dim range:m.range];
        }];

        // Links and images
        [rx(@"!?\\[[^\\]\n]*\\]\\([^)\n]*\\)") enumerateMatchesInString:str options:0 range:lr
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            [ts addAttribute:NSForegroundColorAttributeName value:link range:m.range];
        }];

        // List markers — dim the bullet/number
        [rx(@"^(\\s*)([-*+]|\\d+\\.)(?=\\s)") enumerateMatchesInString:str options:0 range:lr
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *s) {
            NSRange markerRange = [m rangeAtIndex:2];
            [ts addAttribute:NSForegroundColorAttributeName value:dim range:markerRange];
        }];
    }];

    [ts endEditing];
    [um enableUndoRegistration];
}

@end
