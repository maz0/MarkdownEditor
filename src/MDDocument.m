#import "MDDocument.h"
#import "SlashMenu.h"
#import "MDSyntaxHighlighter.h"
#import "MDPreview.h"
#import "MDSchemeHandler.h"
#import "MDTextView.h"
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MDDocument () <SlashMenuDelegate, WKNavigationDelegate, MDTextViewDropDelegate,
                          NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation MDDocument {
    // Core editor
    MDTextView          *_textView;
    NSString            *_content;

    // Toolbar title
    NSTextField         *_titleField;

    // Rename panel
    NSPanel             *_renamePanel;
    NSTextField         *_renameField;
    id                   _renameMonitor;

    // Slash menu
    SlashMenu           *_slashMenu;
    NSUInteger           _slashStart;

    // Syntax highlighting
    MDSyntaxHighlighter *_highlighter;

    // Status bar
    NSTextField         *_statusBar;

    // Font size
    CGFloat              _fontSize;

    // Focus mode
    BOOL                 _focusMode;

    // Preview
    WKWebView           *_webView;
    NSSplitView         *_splitView;
    BOOL                 _previewVisible;
    BOOL                 _shellLoaded;
    NSTimer             *_previewTimer;

    // PDF export (kept alive for the duration of the render)
    WKWebView           *_exportWebView;
    NSWindow            *_exportWindow;
    NSURL               *_exportPDFURL;

    // Outline sidebar
    NSScrollView        *_outlineScroll;
    NSTableView         *_outlineTable;
    NSArray<NSDictionary *> *_outlineItems;
    BOOL                 _outlineVisible;
    BOOL                 _outlineReloading;
}

// ─── NSDocument lifecycle ────────────────────────────────────────────────────

- (instancetype)init {
    self = [super init];
    if (self) {
        _content     = @"";
        _slashMenu   = [SlashMenu new];
        _slashMenu.delegate = self;
        _highlighter = [MDSyntaxHighlighter new];

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        _fontSize  = [ud objectForKey:@"fontSize"] ? [ud floatForKey:@"fontSize"] : 14.0;
        _focusMode = [ud boolForKey:@"focusMode"];
    }
    return self;
}

+ (BOOL)autosavesInPlace { return YES; }

- (void)makeWindowControllers {
    // ── Window ────────────────────────────────────────────────────────────
    NSWindowStyleMask style = NSWindowStyleMaskTitled   | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                              NSWindowStyleMaskUnifiedTitleAndToolbar;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 840, 680)
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.minSize           = NSMakeSize(400, 300);
    window.tabbingMode       = NSWindowTabbingModePreferred;
    window.tabbingIdentifier = @"MDEditor";
    [window center];

    // ── Custom title field in toolbar ─────────────────────────────────────
    _titleField = [self makeTitleField];
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MDDocToolbar"];
    toolbar.delegate                = self;
    toolbar.showsBaselineSeparator  = NO;
    toolbar.centeredItemIdentifier  = @"MDTitleItem";
    window.toolbar        = toolbar;
    window.titleVisibility = NSWindowTitleHidden;
    if (@available(macOS 11.0, *))
        window.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;

    if (self.fileURL)
        window.representedURL = self.fileURL;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResignKey:)
                                                 name:NSWindowDidResignKeyNotification
                                               object:window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResize:)
                                                 name:NSWindowDidResizeNotification
                                               object:window];

    // ── Content layout ────────────────────────────────────────────────────
    NSView *contentView = [[NSView alloc] initWithFrame:window.contentView.bounds];
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat sbh = 22;
    _statusBar = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 840, sbh)];
    _statusBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _statusBar.editable         = NO;
    _statusBar.selectable       = NO;
    _statusBar.bordered         = NO;
    _statusBar.drawsBackground  = YES;
    _statusBar.backgroundColor  = [NSColor windowBackgroundColor];
    _statusBar.textColor        = [NSColor secondaryLabelColor];
    _statusBar.font             = [NSFont systemFontOfSize:11];
    _statusBar.alignment        = NSTextAlignmentCenter;
    _statusBar.stringValue      = @"";

    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, sbh, 840, 680 - sbh)];
    _splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _splitView.vertical         = YES;
    _splitView.dividerStyle     = NSSplitViewDividerStyleThin;

    // ── Outline sidebar (hidden until toggled) ────────────────────────────
    _outlineTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"heading"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineTable addTableColumn:col];
    _outlineTable.headerView               = nil;
    _outlineTable.rowHeight                = 22;
    _outlineTable.dataSource               = self;
    _outlineTable.delegate                 = self;
    _outlineTable.style                    = NSTableViewStyleSourceList;
    _outlineTable.allowsEmptySelection     = YES;

    _outlineScroll = [NSScrollView new];
    _outlineScroll.hasVerticalScroller = YES;
    _outlineScroll.autohidesScrollers  = YES;
    _outlineScroll.borderType          = NSNoBorder;
    _outlineScroll.documentView        = _outlineTable;
    _outlineScroll.hidden              = YES;
    [_splitView addSubview:_outlineScroll];
    [_splitView setHoldingPriority:NSLayoutPriorityDefaultLow + 10 forSubviewAtIndex:0];

    // ── Editor ────────────────────────────────────────────────────────────
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers  = YES;
    scroll.borderType          = NSNoBorder;

    _textView = [[MDTextView alloc] initWithFrame:NSMakeRect(0, 0,
                                                              scroll.contentSize.width,
                                                              scroll.contentSize.height)];
    _textView.dropDelegate = self;
    _textView.minSize               = NSMakeSize(0, scroll.contentSize.height);
    _textView.maxSize               = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _textView.verticallyResizable   = YES;
    _textView.horizontallyResizable = NO;
    _textView.autoresizingMask      = NSViewWidthSizable;
    _textView.textContainer.widthTracksTextView = YES;
    _textView.textContainer.containerSize = NSMakeSize(scroll.contentSize.width, CGFLOAT_MAX);

    _textView.font               = [NSFont monospacedSystemFontOfSize:_fontSize weight:NSFontWeightRegular];
    _textView.backgroundColor    = [NSColor textBackgroundColor];
    _textView.textColor          = [NSColor textColor];
    _textView.richText                           = NO;
    _textView.automaticQuoteSubstitutionEnabled  = NO;
    _textView.automaticDashSubstitutionEnabled   = NO;
    _textView.automaticLinkDetectionEnabled      = NO;
    _textView.automaticSpellingCorrectionEnabled = NO;
    _textView.continuousSpellCheckingEnabled     = NO;
    _textView.grammarCheckingEnabled             = NO;
    _textView.smartInsertDeleteEnabled           = NO;
    _textView.allowsUndo                         = YES;
    _textView.delegate                           = self;

    [_textView setString:_content];
    [_textView.undoManager removeAllActions];

    scroll.documentView = _textView;
    [_splitView addSubview:scroll];

    // ── Preview pane ──────────────────────────────────────────────────────
    WKWebViewConfiguration *webCfg = [WKWebViewConfiguration new];
    [webCfg setURLSchemeHandler:[MDSchemeHandler new] forURLScheme:@"mdpreview"];
    _webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 680)
                                  configuration:webCfg];
    _webView.navigationDelegate = self;
    _webView.hidden = YES;
    [_splitView addSubview:_webView];

    [contentView addSubview:_statusBar];
    [contentView addSubview:_splitView];
    window.contentView = contentView;

    NSWindowController *wc = [[NSWindowController alloc] initWithWindow:window];
    wc.shouldCloseDocument = YES;
    [self addWindowController:wc];

    [self applyFocusModeInset];
    [self runHighlighter];
    [self updateStatusBar];
}

// ─── Toolbar title field ─────────────────────────────────────────────────────

- (NSTextField *)makeTitleField {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 22)];
    f.bezeled         = NO;
    f.bordered        = NO;
    f.drawsBackground = NO;
    f.editable        = NO;
    f.selectable      = NO;
    f.alignment       = NSTextAlignmentCenter;
    f.font            = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    f.textColor       = [NSColor labelColor];
    f.lineBreakMode   = NSLineBreakByTruncatingMiddle;
    f.stringValue     = self.displayName;

    NSClickGestureRecognizer *gr = [[NSClickGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(beginRename:)];
    gr.numberOfClicksRequired = 1;
    [f addGestureRecognizer:gr];
    return f;
}

- (void)updateTitleField {
    if (!_titleField) return;
    // Don't overwrite while user is editing
    if (_titleField.editable) return;
    _titleField.stringValue = self.displayName;
}

// ─── NSToolbarDelegate ────────────────────────────────────────────────────────

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)ident
 willBeInsertedIntoToolbar:(BOOL)flag {
    if ([ident isEqual:@"MDTitleItem"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
        item.view = _titleField;
        return item;
    }
    return nil;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)t {
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"MDTitleItem"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)t {
    return @[NSToolbarFlexibleSpaceItemIdentifier,
             @"MDTitleItem",
             NSToolbarFlexibleSpaceItemIdentifier];
}

// ─── Rename panel ─────────────────────────────────────────────────────────────

- (void)beginRename:(id)sender {
    if (!self.fileURL) { [self saveDocumentAs:nil]; return; }
    if (_renamePanel) return;

    NSWindow *win    = self.windowControllers.firstObject.window;
    NSString *nameOnly = [self.fileURL.lastPathComponent stringByDeletingPathExtension];

    // ── Build panel ───────────────────────────────────────────────────────
    _renamePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 260, 36)
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    _renamePanel.backgroundColor = NSColor.clearColor;
    _renamePanel.opaque          = NO;
    _renamePanel.hasShadow       = YES;
    _renamePanel.level           = NSFloatingWindowLevel;

    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 260, 36)];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    bg.material         = NSVisualEffectMaterialMenu;
    bg.state            = NSVisualEffectStateActive;
    bg.blendingMode     = NSVisualEffectBlendingModeBehindWindow;
    bg.wantsLayer       = YES;
    bg.layer.cornerRadius   = 8;
    bg.layer.masksToBounds  = YES;
    _renamePanel.contentView = bg;

    _renameField = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 6, 244, 24)];
    _renameField.stringValue    = nameOnly;
    _renameField.font           = [NSFont systemFontOfSize:13];
    _renameField.bezelStyle     = NSTextFieldRoundedBezel;
    _renameField.focusRingType  = NSFocusRingTypeNone;
    _renameField.delegate       = self;
    [bg addSubview:_renameField];

    // ── Position centred just inside the top of the content area ─────────
    NSRect winFrame     = win.frame;
    NSRect contentRect  = [win contentRectForFrameRect:winFrame];
    NSPoint origin      = NSMakePoint(NSMidX(winFrame) - 130,
                                      NSMaxY(contentRect) - 44);
    [_renamePanel setFrameOrigin:origin];

    [win addChildWindow:_renamePanel ordered:NSWindowAbove];
    [_renamePanel makeKeyAndOrderFront:nil];
    [_renamePanel makeFirstResponder:_renameField];
    [_renameField selectAll:nil];

    // ── Click outside → commit ────────────────────────────────────────────
    __weak MDDocument *weak = self;
    _renameMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                                          handler:^NSEvent *(NSEvent *ev) {
        MDDocument *doc = weak;
        if (!doc) return ev;
        if (ev.window == doc->_renamePanel) return ev;
        [doc commitRename];
        return ev;
    }];
}

- (void)commitRename {
    if (!_renamePanel) return;
    NSString *newName = [_renameField.stringValue
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    [self dismissRenamePanel];
    if (newName.length > 0) [self renameToName:newName];
}

- (void)dismissRenamePanel {
    if (_renameMonitor) { [NSEvent removeMonitor:_renameMonitor]; _renameMonitor = nil; }
    if (_renamePanel) {
        NSWindow *win = self.windowControllers.firstObject.window;
        [win removeChildWindow:_renamePanel];
        [_renamePanel orderOut:nil];
        _renamePanel = nil;
        _renameField = nil;
    }
    [self.windowControllers.firstObject.window makeFirstResponder:_textView];
}

// NSTextFieldDelegate
- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (note.object != _renameField) return;
    NSInteger movement = [note.userInfo[@"NSTextMovement"] integerValue];
    NSString *newName  = [_renameField.stringValue
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    [self dismissRenamePanel];
    if (movement != NSCancelTextMovement && newName.length > 0)
        [self renameToName:newName];
}

- (void)renameToName:(NSString *)newName {
    NSString *ext         = self.fileURL.pathExtension;
    NSString *currentName = [self.fileURL.lastPathComponent stringByDeletingPathExtension];
    if ([newName isEqualToString:currentName]) return;

    NSString *newFilename = ext.length ? [newName stringByAppendingPathExtension:ext] : newName;
    NSURL    *newURL      = [[self.fileURL URLByDeletingLastPathComponent]
                             URLByAppendingPathComponent:newFilename];
    NSError  *err         = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:self.fileURL toURL:newURL error:&err]) {
        [self presentError:err];
        _titleField.stringValue = self.displayName;
        return;
    }
    // Update document — triggers setFileURL: which syncs the title field
    [self setFileURL:newURL];
}

- (void)setFileURL:(NSURL *)url {
    [super setFileURL:url];
    [self updateTitleField];
    for (NSWindowController *wc in self.windowControllers) {
        wc.window.representedURL = url;
    }
    if (_previewVisible && _shellLoaded)
        [self pushPreviewContent]; // relative image paths resolve against the new dir
}

// ─── Read / Write ────────────────────────────────────────────────────────────

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!str) str = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!str) {
        if (outError)
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadUnknownStringEncodingError
                                        userInfo:nil];
        return NO;
    }
    _content = str;
    if (_textView) {
        [_textView setString:str];
        [_textView.undoManager removeAllActions];
        [self updateChangeCount:NSChangeCleared];
        [self updateTitleField];
        [self runHighlighter];
        [self updateStatusBar];
    }
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    NSString *text = _textView ? _textView.string : _content;
    NSData   *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data && outError)
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileWriteUnknownError
                                    userInfo:nil];
    return data;
}

// ─── Window notifications ────────────────────────────────────────────────────

- (void)windowDidResignKey:(NSNotification *)note {
    [_slashMenu dismiss];
}

- (void)windowDidResize:(NSNotification *)note {
    if (_focusMode) [self applyFocusModeInset];
}

// ─── NSTextViewDelegate ──────────────────────────────────────────────────────

- (void)textDidChange:(NSNotification *)note {
    [self updateChangeCount:NSChangeDone];
    [self runHighlighter];
    [self updateStatusBar];
    [self checkSlashTrigger];
    if (_focusMode) [self centerCaretLine];
    if (_previewVisible) [self schedulePreviewUpdate];
    [self rebuildOutline];
}

// Typewriter scrolling: while writing in focus mode, keep the caret line
// vertically centred instead of letting it sink to the bottom edge.
- (void)centerCaretLine {
    NSLayoutManager *lm  = _textView.layoutManager;
    NSString *text       = _textView.string;
    NSUInteger loc       = _textView.selectedRange.location;

    NSRect line;
    if (loc >= text.length) {
        if (lm.extraLineFragmentTextContainer)
            line = lm.extraLineFragmentRect;
        else if (text.length == 0)
            return;
        else
            line = [lm lineFragmentRectForGlyphAtIndex:
                    [lm glyphIndexForCharacterAtIndex:text.length - 1]
                                        effectiveRange:NULL];
    } else {
        line = [lm lineFragmentRectForGlyphAtIndex:
                [lm glyphIndexForCharacterAtIndex:loc]
                                    effectiveRange:NULL];
    }

    NSClipView *clip = _textView.enclosingScrollView.contentView;
    CGFloat caretY = NSMidY(line) + _textView.textContainerInset.height;
    CGFloat target = caretY - clip.bounds.size.height / 2;
    target = MAX(0, MIN(target, _textView.frame.size.height - clip.bounds.size.height));
    [clip scrollToPoint:NSMakePoint(clip.bounds.origin.x, target)];
    [_textView.enclosingScrollView reflectScrolledClipView:clip];
}

- (void)textViewDidChangeSelection:(NSNotification *)note {
    [self updateStatusBar];
    if (!_slashMenu.isVisible) return;
    if (_textView.selectedRange.location < _slashStart + 1)
        [_slashMenu dismiss];
}

- (BOOL)textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    if (_slashMenu.isVisible) {
        if (sel == @selector(moveUp:))          { [_slashMenu moveUp];   return YES; }
        if (sel == @selector(moveDown:))        { [_slashMenu moveDown]; return YES; }
        if (sel == @selector(insertNewline:))   { [_slashMenu confirm];  return YES; }
        if (sel == @selector(insertTab:))       { [_slashMenu confirm];  return YES; }
        if (sel == @selector(cancelOperation:)) { [_slashMenu dismiss];  return YES; }
    }
    if (sel == @selector(insertNewline:))
        return [self handleListContinuation];
    return NO;
}

// ─── Auto-list continuation ───────────────────────────────────────────────────

- (BOOL)handleListContinuation {
    NSString   *text   = _textView.string;
    NSUInteger  cursor = _textView.selectedRange.location;
    if (cursor == 0) return NO;

    NSRange   lineRange = [text lineRangeForRange:NSMakeRange(cursor - 1, 0)];
    NSString *line      = [[text substringWithRange:lineRange]
                           stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];

    NSRegularExpression *ul = [NSRegularExpression
        regularExpressionWithPattern:@"^(\\s*)([-*+])\\s+" options:0 error:nil];
    NSTextCheckingResult *um = [ul firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (um) {
        NSString *indent = [line substringWithRange:[um rangeAtIndex:1]];
        NSString *bullet = [line substringWithRange:[um rangeAtIndex:2]];
        NSString *rest   = [line substringFromIndex:NSMaxRange(um.range)];
        NSRange ins      = NSMakeRange(cursor, 0);
        if (rest.length == 0) {
            NSRange del = NSMakeRange(lineRange.location, cursor - lineRange.location);
            if ([_textView shouldChangeTextInRange:del replacementString:@""])
                { [_textView replaceCharactersInRange:del withString:@""]; [_textView didChangeText]; }
            return YES;
        }
        NSString *cont = [NSString stringWithFormat:@"\n%@%@ ", indent, bullet];
        if ([_textView shouldChangeTextInRange:ins replacementString:cont])
            { [_textView replaceCharactersInRange:ins withString:cont]; [_textView didChangeText]; }
        return YES;
    }

    NSRegularExpression *ol = [NSRegularExpression
        regularExpressionWithPattern:@"^(\\s*)(\\d+)\\.\\s+" options:0 error:nil];
    NSTextCheckingResult *om = [ol firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (om) {
        NSString *indent = [line substringWithRange:[om rangeAtIndex:1]];
        NSUInteger num   = (NSUInteger)[[line substringWithRange:[om rangeAtIndex:2]] integerValue];
        NSString *rest   = [line substringFromIndex:NSMaxRange(om.range)];
        NSRange ins      = NSMakeRange(cursor, 0);
        if (rest.length == 0) {
            NSRange del = NSMakeRange(lineRange.location, cursor - lineRange.location);
            if ([_textView shouldChangeTextInRange:del replacementString:@""])
                { [_textView replaceCharactersInRange:del withString:@""]; [_textView didChangeText]; }
            return YES;
        }
        NSString *cont = [NSString stringWithFormat:@"\n%@%lu. ", indent, (unsigned long)(num + 1)];
        if ([_textView shouldChangeTextInRange:ins replacementString:cont])
            { [_textView replaceCharactersInRange:ins withString:cont]; [_textView didChangeText]; }
        return YES;
    }
    return NO;
}

// ─── Syntax highlighting ──────────────────────────────────────────────────────

- (void)runHighlighter {
    if (!_textView) return;
    NSFont *font = [NSFont monospacedSystemFontOfSize:_fontSize weight:NSFontWeightRegular];
    [_highlighter highlight:_textView.textStorage font:font];
    _textView.typingAttributes = @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: NSColor.textColor
    };
}

// ─── Status bar ───────────────────────────────────────────────────────────────

- (void)updateStatusBar {
    if (!_statusBar) return;
    NSString *text = _textView.string ?: @"";

    NSArray<NSString *> *words = [text componentsSeparatedByCharactersInSet:
                                  NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger wordCount = 0;
    for (NSString *w in words) if (w.length > 0) wordCount++;

    NSUInteger cursor  = _textView.selectedRange.location;
    NSUInteger lineNum = 1, colNum = 1;
    NSUInteger lastNL  = NSNotFound;
    for (NSUInteger i = 0; i < MIN(cursor, text.length); i++) {
        if ([text characterAtIndex:i] == '\n') { lineNum++; lastNL = i; }
    }
    colNum = (lastNL == NSNotFound) ? cursor + 1 : cursor - lastNL;

    _statusBar.stringValue = [NSString stringWithFormat:
        @"Words: %lu   Chars: %lu   Ln %lu, Col %lu",
        (unsigned long)wordCount, (unsigned long)text.length,
        (unsigned long)lineNum, (unsigned long)colNum];
}

// ─── Font size ────────────────────────────────────────────────────────────────

- (void)increaseFontSize:(id)sender { _fontSize = MIN(_fontSize + 1, 36); [self applyFontSize]; }
- (void)decreaseFontSize:(id)sender { _fontSize = MAX(_fontSize - 1,  8); [self applyFontSize]; }
- (void)resetFontSize:(id)sender    { _fontSize = 14.0;                    [self applyFontSize]; }

- (void)applyFontSize {
    if (!_textView) return;
    _textView.font = [NSFont monospacedSystemFontOfSize:_fontSize weight:NSFontWeightRegular];
    [[NSUserDefaults standardUserDefaults] setFloat:_fontSize forKey:@"fontSize"];
    [self runHighlighter];
}

// ─── Focus mode ───────────────────────────────────────────────────────────────

- (void)toggleFocusMode:(id)sender {
    _focusMode = !_focusMode;
    [[NSUserDefaults standardUserDefaults] setBool:_focusMode forKey:@"focusMode"];
    [self applyFocusModeInset];
}

- (void)applyFocusModeInset {
    if (!_textView) return;
    if (_focusMode) {
        CGFloat editorWidth = _previewVisible
            ? _splitView.frame.size.width / 2
            : _splitView.frame.size.width;
        CGFloat inset = MAX(18, (editorWidth - 680) / 2);
        _textView.textContainerInset = NSMakeSize(inset, 40);
    } else {
        _textView.textContainerInset = NSMakeSize(18, 18);
    }
}

// ─── Preview ─────────────────────────────────────────────────────────────────

- (void)togglePreview:(id)sender {
    _previewVisible = !_previewVisible;
    _webView.hidden = !_previewVisible;
    [_splitView adjustSubviews];
    // Divider 1: editor/preview (divider 0 is the outline sidebar)
    if (_previewVisible) {
        [_splitView setPosition:_splitView.frame.size.width * 0.55 ofDividerAtIndex:1];
        [self updatePreview];
    } else {
        [_splitView setPosition:_splitView.frame.size.width ofDividerAtIndex:1];
    }
    [self applyFocusModeInset];
}

// ─── Outline sidebar ─────────────────────────────────────────────────────────

- (void)toggleOutline:(id)sender {
    _outlineVisible = !_outlineVisible;
    _outlineScroll.hidden = !_outlineVisible;
    [_splitView adjustSubviews];
    if (_outlineVisible) {
        [self rebuildOutline];
        [_splitView setPosition:180 ofDividerAtIndex:0];
    } else {
        [_splitView setPosition:0 ofDividerAtIndex:0];
    }
    [self applyFocusModeInset];
}

- (void)rebuildOutline {
    if (!_outlineVisible) return;
    NSString *text = _textView.string ?: @"";
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    __block BOOL inFence = NO;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
                          usingBlock:^(NSString *sub, NSRange lineRange, NSRange enclosing, BOOL *stop) {
        NSString *line = [text substringWithRange:lineRange];
        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) { inFence = !inFence; return; }
        if (inFence) return;
        NSUInteger h = 0;
        while (h < MIN(6, line.length) && [line characterAtIndex:h] == '#') h++;
        if (h > 0 && h < line.length && [line characterAtIndex:h] == ' ') {
            [items addObject:@{
                @"title":    [line substringFromIndex:h + 1],
                @"level":    @(h),
                @"location": @(lineRange.location),
            }];
        }
    }];
    if ([items isEqualToArray:_outlineItems]) return;
    _outlineItems = items;
    _outlineReloading = YES;
    [_outlineTable reloadData];
    _outlineReloading = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_outlineItems.count;
}

- (NSView *)tableView:(NSTableView *)tv
   viewForTableColumn:(NSTableColumn *)column
                  row:(NSInteger)row {
    NSTextField *label = [tv makeViewWithIdentifier:@"outlineCell" owner:self];
    if (!label) {
        label = [NSTextField labelWithString:@""];
        label.identifier    = @"outlineCell";
        label.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    NSDictionary *item = _outlineItems[(NSUInteger)row];
    NSUInteger level   = [item[@"level"] unsignedIntegerValue];
    label.stringValue  = item[@"title"];
    label.font = level == 1
        ? [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]
        : [NSFont systemFontOfSize:12];
    label.textColor = level <= 2 ? NSColor.labelColor : NSColor.secondaryLabelColor;

    NSView *cell = [NSView new];
    [cell addSubview:label];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor
                                            constant:4 + 12.0 * (CGFloat)(level - 1)],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    if (_outlineReloading) return;
    NSInteger row = _outlineTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= _outlineItems.count) return;
    NSUInteger loc = [_outlineItems[(NSUInteger)row][@"location"] unsignedIntegerValue];
    loc = MIN(loc, _textView.string.length);
    [_textView setSelectedRange:NSMakeRange(loc, 0)];
    [_textView scrollRangeToVisible:NSMakeRange(loc, 0)];
    [self.windowControllers.firstObject.window makeFirstResponder:_textView];
}

- (void)schedulePreviewUpdate {
    [_previewTimer invalidate];
    _previewTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                     target:self
                                                   selector:@selector(updatePreview)
                                                   userInfo:nil
                                                    repeats:NO];
}

// The shell (CSS + JS engines) is loaded once; edits then patch the DOM via
// window.mdUpdate so the page never navigates and scroll position survives.
- (void)updatePreview {
    if (!_previewVisible || !_webView) return;
    if (!_shellLoaded) {
        [_webView loadHTMLString:[MDPreview shellHTML]
                         baseURL:[NSURL URLWithString:@"mdpreview:///"]];
        return; // didFinishNavigation pushes the first content
    }
    [self pushPreviewContent];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (webView == _webView) {
        _shellLoaded = YES;
        [self pushPreviewContent];
    } else if (webView == _exportWebView) {
        // Give mermaid a moment to render diagrams before capturing
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self finishPDFExport]; });
    }
}

- (void)pushPreviewContent {
    NSString *body = [MDPreview bodyFromMarkdown:_textView.string ?: @""];
    NSString *base = [self previewBaseURL].absoluteString ?: @"";
    NSString *js = [NSString stringWithFormat:@"window.mdUpdate(%@,%@);",
                    [MDPreview jsStringLiteral:body],
                    [MDPreview jsStringLiteral:base]];
    [_webView evaluateJavaScript:js completionHandler:nil];
}

// ─── Image drop ──────────────────────────────────────────────────────────────

- (NSString *)markdownForDroppedImageAtURL:(NSURL *)url {
    NSString *alt = [url.lastPathComponent stringByDeletingPathExtension];

    // Unsaved document: reference the image where it is, by absolute path
    // (resolves through the mdpreview:// base in the preview).
    if (!self.fileURL)
        return [NSString stringWithFormat:@"![%@](%@)", alt,
                [url.path stringByAddingPercentEncodingWithAllowedCharacters:
                 NSCharacterSet.URLPathAllowedCharacterSet]];

    // Saved document: copy the image beside it (unless it's already there)
    // and reference it relatively.
    NSFileManager *fm  = NSFileManager.defaultManager;
    NSURL *dir         = self.fileURL.URLByDeletingLastPathComponent;
    NSString *name     = url.lastPathComponent;
    NSURL *dest        = [dir URLByAppendingPathComponent:name];

    if (![dest.path isEqualToString:url.path]) {
        NSUInteger n = 1;
        while ([fm fileExistsAtPath:dest.path] &&
               ![fm contentsEqualAtPath:dest.path andPath:url.path]) {
            name = [NSString stringWithFormat:@"%@-%lu.%@",
                    [url.lastPathComponent stringByDeletingPathExtension],
                    (unsigned long)n++, url.pathExtension];
            dest = [dir URLByAppendingPathComponent:name];
        }
        if (![fm fileExistsAtPath:dest.path]) {
            NSError *err = nil;
            if (![fm copyItemAtURL:url toURL:dest error:&err]) {
                [self presentError:err];
                return nil;
            }
        }
    }
    return [NSString stringWithFormat:@"![%@](%@)", alt,
            [name stringByAddingPercentEncodingWithAllowedCharacters:
             NSCharacterSet.URLPathAllowedCharacterSet]];
}

// ─── Export ──────────────────────────────────────────────────────────────────

- (NSString *)exportBaseName {
    return self.fileURL
        ? [self.fileURL.lastPathComponent stringByDeletingPathExtension]
        : [self.displayName stringByDeletingPathExtension];
}

- (NSURL *)previewBaseURL {
    if (!self.fileURL) return nil;
    NSURLComponents *c = [NSURLComponents new];
    c.scheme = @"mdpreview";
    c.host   = @"";
    c.path   = [self.fileURL.URLByDeletingLastPathComponent.path
                stringByAppendingString:@"/"];
    return c.URL;
}

- (void)exportHTML:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeHTML];
    panel.nameFieldStringValue = [[self exportBaseName] stringByAppendingPathExtension:@"html"];
    [panel beginSheetModalForWindow:self.windowControllers.firstObject.window
                  completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK || !panel.URL) return;
        NSString *html = [MDPreview htmlFromMarkdown:self->_textView.string ?: @""];
        NSError *err = nil;
        if (![html writeToURL:panel.URL atomically:YES
                     encoding:NSUTF8StringEncoding error:&err])
            [self presentError:err];
    }];
}

- (void)exportPDF:(id)sender {
    if (_exportWebView) return; // one export at a time
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePDF];
    panel.nameFieldStringValue = [[self exportBaseName] stringByAppendingPathExtension:@"pdf"];
    [panel beginSheetModalForWindow:self.windowControllers.firstObject.window
                  completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK || !panel.URL) return;
        [self renderPDFToURL:panel.URL];
    }];
}

- (void)renderPDFToURL:(NSURL *)url {
    _exportPDFURL = url;

    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    [cfg setURLSchemeHandler:[MDSchemeHandler new] forURLScheme:@"mdpreview"];
    _exportWebView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 650, 850)
                                        configuration:cfg];
    _exportWebView.navigationDelegate = self;

    // WKWebView only prints when attached to a window; keep it offscreen
    _exportWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(-2000, -2000, 650, 850)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    _exportWindow.contentView = _exportWebView;

    [_exportWebView loadHTMLString:[MDPreview htmlFromMarkdown:_textView.string ?: @""]
                           baseURL:[self previewBaseURL]];
    // didFinishNavigation → runPDFPrintOperation
}

// createPDFWithConfiguration: produces one continuous page (no pagination),
// but NSPrintOperation on a WKWebView is broken on this macOS — it spins
// producing a multi-GB file. Resize the view to the full content height
// first, since createPDF only captures the view bounds.
- (void)finishPDFExport {
    [_exportWebView evaluateJavaScript:@"document.documentElement.scrollHeight"
                     completionHandler:^(id height, NSError *err) {
        CGFloat h = [height isKindOfClass:NSNumber.class] ? [height doubleValue] : 850;
        NSRect frame = NSMakeRect(0, 0, self->_exportWebView.frame.size.width,
                                  MAX(h, 100));
        [self->_exportWindow setFrame:NSMakeRect(-3000, -3000, frame.size.width,
                                                 frame.size.height) display:NO];
        self->_exportWebView.frame = frame;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WKPDFConfiguration *cfg = [WKPDFConfiguration new];
            [self->_exportWebView createPDFWithConfiguration:cfg
                                           completionHandler:^(NSData *pdf, NSError *e) {
                if (pdf) {
                    NSError *werr = nil;
                    if (![pdf writeToURL:self->_exportPDFURL
                                 options:NSDataWritingAtomic error:&werr])
                        [self presentError:werr];
                } else if (e) {
                    [self presentError:e];
                }
                self->_exportWebView = nil;
                self->_exportWindow  = nil;
                self->_exportPDFURL  = nil;
            }];
        });
    }];
}

// ─── validateMenuItem ─────────────────────────────────────────────────────────

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleFocusMode:))
        item.state = _focusMode ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(togglePreview:))
        item.state = _previewVisible ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(toggleOutline:))
        item.state = _outlineVisible ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}

// ─── Slash trigger ────────────────────────────────────────────────────────────

- (void)checkSlashTrigger {
    NSString   *text   = _textView.string;
    NSUInteger  cursor = _textView.selectedRange.location;
    if (cursor == 0) { [_slashMenu dismiss]; return; }

    NSRange   lineRange = [text lineRangeForRange:NSMakeRange(cursor, 0)];
    NSString *lineUpTo  = [text substringWithRange:
                            NSMakeRange(lineRange.location, cursor - lineRange.location)];
    if ([lineUpTo hasPrefix:@"/"]) {
        NSString *query = [lineUpTo substringFromIndex:1];
        if ([query rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location
            == NSNotFound) {
            _slashStart = lineRange.location;
            if (!_slashMenu.isVisible) {
                NSRect caret = [_textView firstRectForCharacterRange:NSMakeRange(_slashStart, 1)
                                                         actualRange:nil];
                [_slashMenu showBelowRect:caret
                             parentWindow:self.windowControllers.firstObject.window];
            }
            [_slashMenu filterWithQuery:query];
            return;
        }
    }
    [_slashMenu dismiss];
}

// ─── SlashMenuDelegate ────────────────────────────────────────────────────────

- (void)slashMenu:(SlashMenu *)menu
   didSelectPrefix:(NSString *)prefix
            suffix:(NSString *)suffix
       placeholder:(NSString *)placeholder {
    NSUInteger cursor   = _textView.selectedRange.location;
    NSRange    replace  = NSMakeRange(_slashStart, cursor - _slashStart);
    NSString  *inserted = [NSString stringWithFormat:@"%@%@%@", prefix, placeholder, suffix];
    if ([_textView shouldChangeTextInRange:replace replacementString:inserted]) {
        [_textView replaceCharactersInRange:replace withString:inserted];
        [_textView didChangeText];
        NSRange sel = placeholder.length
            ? NSMakeRange(_slashStart + prefix.length, placeholder.length)
            : NSMakeRange(_slashStart + prefix.length, 0);
        [_textView setSelectedRange:sel];
    }
}

- (void)slashMenuDidDismiss:(SlashMenu *)menu {}

// ─── Markdown shortcuts ───────────────────────────────────────────────────────

- (void)wrapWith:(NSString *)prefix suffix:(NSString *)suffix placeholder:(NSString *)ph {
    NSRange   sel  = _textView.selectedRange;
    NSString *text = [_textView.string substringWithRange:sel];
    NSString *rep;
    NSRange   newSel;
    if (sel.length > 0) {
        rep    = [NSString stringWithFormat:@"%@%@%@", prefix, text, suffix];
        newSel = NSMakeRange(sel.location + prefix.length, sel.length);
    } else {
        rep    = [NSString stringWithFormat:@"%@%@%@", prefix, ph, suffix];
        newSel = NSMakeRange(sel.location + prefix.length, ph.length);
    }
    if ([_textView shouldChangeTextInRange:sel replacementString:rep]) {
        [_textView replaceCharactersInRange:sel withString:rep];
        [_textView didChangeText];
        [_textView setSelectedRange:newSel];
    }
}

- (void)mdBold:(id)sender   { [self wrapWith:@"**" suffix:@"**" placeholder:@"bold text"];   }
- (void)mdItalic:(id)sender { [self wrapWith:@"*"  suffix:@"*"  placeholder:@"italic text"]; }

- (void)mdLink:(id)sender {
    NSRange   sel  = _textView.selectedRange;
    NSString *text = [_textView.string substringWithRange:sel];
    NSString *rep;
    NSRange   newSel;
    if (sel.length > 0) {
        rep    = [NSString stringWithFormat:@"[%@](url)", text];
        newSel = NSMakeRange(sel.location + sel.length + 3, 3);
    } else {
        rep    = @"[link text](url)";
        newSel = NSMakeRange(sel.location + 1, 9);
    }
    if ([_textView shouldChangeTextInRange:sel replacementString:rep]) {
        [_textView replaceCharactersInRange:sel withString:rep];
        [_textView didChangeText];
        [_textView setSelectedRange:newSel];
    }
}

@end
