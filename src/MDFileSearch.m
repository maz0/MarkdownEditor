#import "MDFileSearch.h"
#import "MDDocument.h"

static const NSUInteger kMaxResults  = 300;
static const NSUInteger kMaxFileSize = 2 * 1024 * 1024;

@interface MDFileSearch () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation MDFileSearch {
    NSPanel       *_panel;
    NSSearchField *_field;
    NSTableView   *_table;
    NSTextField   *_status;
    NSURL         *_folder;
    NSArray<NSDictionary *> *_results;
}

// ─── Panel ───────────────────────────────────────────────────────────────────

- (void)buildPanel {
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 400)
                                        styleMask:NSWindowStyleMaskTitled |
                                                  NSWindowStyleMaskClosable |
                                                  NSWindowStyleMaskResizable |
                                                  NSWindowStyleMaskUtilityWindow
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.releasedWhenClosed = NO;
    _panel.minSize = NSMakeSize(380, 240);
    [_panel center];

    NSView *content = _panel.contentView;

    _field = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _field.placeholderString = @"Search in folder… (press Return)";
    _field.target = self;
    _field.action = @selector(runSearch:);
    _field.sendsWholeSearchString = YES;

    _table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"match"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.rowHeight  = 22;
    _table.dataSource = self;
    _table.delegate   = self;
    _table.target     = self;
    _table.action     = @selector(openSelectedResult:);

    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers  = YES;
    scroll.borderType          = NSBezelBorder;
    scroll.documentView        = _table;

    _status = [NSTextField labelWithString:@""];
    _status.font      = [NSFont systemFontOfSize:11];
    _status.textColor = NSColor.secondaryLabelColor;

    for (NSView *v in @[_field, scroll, _status]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_field.topAnchor      constraintEqualToAnchor:content.topAnchor constant:10],
        [_field.leadingAnchor  constraintEqualToAnchor:content.leadingAnchor constant:10],
        [_field.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [scroll.topAnchor      constraintEqualToAnchor:_field.bottomAnchor constant:8],
        [scroll.leadingAnchor  constraintEqualToAnchor:content.leadingAnchor constant:10],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [scroll.bottomAnchor   constraintEqualToAnchor:_status.topAnchor constant:-6],
        [_status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [_status.bottomAnchor  constraintEqualToAnchor:content.bottomAnchor constant:-8],
    ]];
}

- (void)show {
    if (!_panel) [self buildPanel];

    // Prefer the frontmost document's folder; fall back to the last one used,
    // then to asking.
    NSDocument *doc = [NSDocumentController sharedDocumentController].currentDocument;
    if (doc.fileURL)
        _folder = doc.fileURL.URLByDeletingLastPathComponent;
    if (!_folder) {
        NSOpenPanel *open = [NSOpenPanel openPanel];
        open.canChooseFiles = NO;
        open.canChooseDirectories = YES;
        open.prompt = @"Search Here";
        if ([open runModal] != NSModalResponseOK) return;
        _folder = open.URL;
    }
    _panel.title = [NSString stringWithFormat:@"Find in “%@”", _folder.lastPathComponent];
    [_panel makeKeyAndOrderFront:nil];
    [_panel makeFirstResponder:_field];
}

// ─── Search ──────────────────────────────────────────────────────────────────

- (void)runSearch:(id)sender {
    NSString *query = _field.stringValue;
    if (query.length == 0) { _results = @[]; [_table reloadData]; _status.stringValue = @""; return; }

    static NSSet<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [NSSet setWithArray:@[@"md", @"markdown", @"mdown", @"mkd", @"txt", @"text"]];
    });

    NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
    NSUInteger filesScanned = 0;
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager]
        enumeratorAtURL:_folder
        includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles |
                NSDirectoryEnumerationSkipsPackageDescendants
        errorHandler:nil];

    for (NSURL *url in en) {
        if (results.count >= kMaxResults) break;
        if (![exts containsObject:url.pathExtension.lowercaseString]) continue;
        NSNumber *isFile = nil, *size = nil;
        [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&size   forKey:NSURLFileSizeKey error:nil];
        if (!isFile.boolValue || size.unsignedIntegerValue > kMaxFileSize) continue;

        NSString *text = [NSString stringWithContentsOfURL:url
                                                  encoding:NSUTF8StringEncoding error:nil];
        if (!text) continue;
        filesScanned++;

        __block NSUInteger lineNum = 0;
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                                 options:NSStringEnumerationByLines |
                                         NSStringEnumerationSubstringNotRequired
                              usingBlock:^(NSString *sub, NSRange lineRange,
                                           NSRange enclosing, BOOL *stop) {
            lineNum++;
            NSString *line = [text substringWithRange:lineRange];
            NSRange hit = [line rangeOfString:query options:NSCaseInsensitiveSearch];
            if (hit.location == NSNotFound) return;
            NSString *snippet = [line stringByTrimmingCharactersInSet:
                                 NSCharacterSet.whitespaceCharacterSet];
            if (snippet.length > 120) snippet = [[snippet substringToIndex:120]
                                                 stringByAppendingString:@"…"];
            [results addObject:@{
                @"url":     url,
                @"line":    @(lineNum),
                @"loc":     @(lineRange.location + hit.location),
                @"len":     @(hit.length),
                @"snippet": snippet,
            }];
            if (results.count >= kMaxResults) *stop = YES;
        }];
    }

    _results = results;
    [_table reloadData];
    _status.stringValue = [NSString stringWithFormat:@"%lu match%s in %lu file%s%s",
        (unsigned long)results.count, results.count == 1 ? "" : "es",
        (unsigned long)filesScanned, filesScanned == 1 ? "" : "s",
        results.count >= kMaxResults ? " (capped)" : ""];
}

// ─── Open result ─────────────────────────────────────────────────────────────

- (void)openSelectedResult:(id)sender {
    NSInteger row = _table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow;
    if (row < 0 || (NSUInteger)row >= _results.count) return;
    NSDictionary *r = _results[(NSUInteger)row];
    NSRange match = NSMakeRange([r[@"loc"] unsignedIntegerValue],
                                [r[@"len"] unsignedIntegerValue]);
    [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:r[@"url"]
                              display:YES
                    completionHandler:^(NSDocument *doc, BOOL alreadyOpen, NSError *err) {
        if (err) { [NSApp presentError:err]; return; }
        if ([doc isKindOfClass:MDDocument.class])
            [(MDDocument *)doc jumpToCharacterRange:match];
    }];
}

// ─── Table ───────────────────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_results.count;
}

- (NSView *)tableView:(NSTableView *)tv
   viewForTableColumn:(NSTableColumn *)col
                  row:(NSInteger)row {
    NSTextField *label = [tv makeViewWithIdentifier:@"resultCell" owner:self];
    if (!label) {
        label = [NSTextField labelWithString:@""];
        label.identifier    = @"resultCell";
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.font          = [NSFont systemFontOfSize:12];
    }
    NSDictionary *r = _results[(NSUInteger)row];
    NSString *name = [r[@"url"] lastPathComponent];
    NSString *text = [NSString stringWithFormat:@"%@:%@ — %@",
                      name, r[@"line"], r[@"snippet"]];
    NSMutableAttributedString *att = [[NSMutableAttributedString alloc]
        initWithString:text attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
    [att addAttributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: NSColor.labelColor}
                 range:NSMakeRange(0, name.length)];
    label.attributedStringValue = att;
    return label;
}

@end
