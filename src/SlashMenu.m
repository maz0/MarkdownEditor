#import "SlashMenu.h"

// ─── Item model ───────────────────────────────────────────────────────────────

@interface SlashItem : NSObject
@property (copy) NSString *label;
@property (copy) NSString *prefix;
@property (copy) NSString *suffix;
@property (copy) NSString *placeholder;
@property (getter=isSeparator) BOOL separator;
+ (instancetype)label:(NSString *)l prefix:(NSString *)p suffix:(NSString *)s placeholder:(NSString *)ph;
+ (instancetype)sep;
@end

@implementation SlashItem
+ (instancetype)label:(NSString *)l prefix:(NSString *)p suffix:(NSString *)s placeholder:(NSString *)ph {
    SlashItem *i = [SlashItem new]; i.label = l; i.prefix = p; i.suffix = s; i.placeholder = ph; return i;
}
+ (instancetype)sep { SlashItem *i = [SlashItem new]; i.separator = YES; return i; }
@end

static NSArray<SlashItem *> *allItems(void) {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = @[
            [SlashItem label:@"Heading 1"     prefix:@"# "      suffix:@""       placeholder:@"Heading"],
            [SlashItem label:@"Heading 2"     prefix:@"## "     suffix:@""       placeholder:@"Heading"],
            [SlashItem label:@"Heading 3"     prefix:@"### "    suffix:@""       placeholder:@"Heading"],
            [SlashItem sep],
            [SlashItem label:@"Bold"          prefix:@"**"      suffix:@"**"     placeholder:@"bold text"],
            [SlashItem label:@"Italic"        prefix:@"*"       suffix:@"*"      placeholder:@"italic text"],
            [SlashItem label:@"Inline code"   prefix:@"`"       suffix:@"`"      placeholder:@"code"],
            [SlashItem sep],
            [SlashItem label:@"Bullet list"   prefix:@"- "      suffix:@""       placeholder:@"Item"],
            [SlashItem label:@"Numbered list" prefix:@"1. "     suffix:@""       placeholder:@"Item"],
            [SlashItem label:@"Blockquote"    prefix:@"> "      suffix:@""       placeholder:@"Quote"],
            [SlashItem label:@"Code block"    prefix:@"```\n"   suffix:@"\n```"  placeholder:@""],
            [SlashItem label:@"Table"
                       prefix:@"| Col 1 | Col 2 |\n| --- | --- |\n| "
                       suffix:@" |  |"
                  placeholder:@"Cell"],
            [SlashItem label:@"Divider"       prefix:@"\n---\n" suffix:@""       placeholder:@""],
            [SlashItem sep],
            [SlashItem label:@"Link"          prefix:@"["       suffix:@"](url)" placeholder:@"link text"],
            [SlashItem label:@"Image"         prefix:@"!["      suffix:@"](url)" placeholder:@"alt text"],
        ];
    });
    return items;
}

// ─── Panel ────────────────────────────────────────────────────────────────────

@interface SlashMenu () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation SlashMenu {
    NSPanel               *_panel;
    NSTableView           *_table;
    NSArray<SlashItem *>  *_filtered;
    NSInteger              _selectedIndex;
}

static const CGFloat kPanelWidth  = 220;
static const CGFloat kRowHeight   = 28;
static const CGFloat kSepHeight   = 9;
static const CGFloat kMaxHeight   = 320;
static const CGFloat kPadding     = 4;

- (instancetype)init {
    self = [super init];
    if (self) { _filtered = @[]; _selectedIndex = -1; [self buildPanel]; }
    return self;
}

- (void)buildPanel {
    NSPanel *p = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, kPanelWidth, kMaxHeight)
                  styleMask:NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:YES];
    p.hasShadow = YES;
    p.opaque = NO;
    p.backgroundColor = [NSColor clearColor];
    p.level = NSFloatingWindowLevel;
    p.releasedWhenClosed = NO;

    NSVisualEffectView *vev = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, kPanelWidth, kMaxHeight)];
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vev.material   = NSVisualEffectMaterialMenu;
    vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vev.state      = NSVisualEffectStateActive;
    vev.wantsLayer = YES;
    vev.layer.cornerRadius = 10;
    vev.layer.masksToBounds = YES;

    NSScrollView *scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(kPadding, kPadding,
                                 kPanelWidth - kPadding*2,
                                 kMaxHeight  - kPadding*2)];
    scroll.autoresizingMask  = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = NO;
    scroll.drawsBackground   = NO;
    scroll.borderType        = NSNoBorder;

    CGFloat tw = kPanelWidth - kPadding*2;
    NSTableView *t = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, tw, kMaxHeight)];
    t.autoresizingMask = NSViewWidthSizable;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    col.width = tw;
    col.resizingMask = NSTableColumnAutoresizingMask;
    [t addTableColumn:col];
    t.headerView          = nil;
    t.gridStyleMask       = NSTableViewGridNone;
    t.backgroundColor     = [NSColor clearColor];
    t.intercellSpacing    = NSMakeSize(0, 0);
    t.dataSource          = self;
    t.delegate            = self;
    t.target              = self;
    t.action              = @selector(rowClicked:);

    scroll.documentView = t;
    [vev addSubview:scroll];
    p.contentView = vev;

    _panel = p;
    _table = t;
}

- (BOOL)isVisible { return _panel.isVisible; }

// ─── Show / hide ──────────────────────────────────────────────────────────────

- (void)showBelowRect:(NSRect)sr parentWindow:(NSWindow *)parent {
    [self applyFilter:@""];
    if (_filtered.count == 0) return;
    [self refit];

    CGFloat x = sr.origin.x;
    CGFloat y = sr.origin.y - _panel.frame.size.height - 4;
    if (NSScreen.mainScreen && y < NSScreen.mainScreen.visibleFrame.origin.y)
        y = sr.origin.y + sr.size.height + 4;

    [_panel setFrameOrigin:NSMakePoint(x, y)];
    if (parent) [parent addChildWindow:_panel ordered:NSWindowAbove];
    [_panel orderFront:nil];
    [self selectFirst];
}

- (void)dismiss {
    if (!_panel.isVisible) return;
    if (_panel.parentWindow) [_panel.parentWindow removeChildWindow:_panel];
    [_panel orderOut:nil];
    [_delegate slashMenuDidDismiss:self];
}

// ─── Filtering ────────────────────────────────────────────────────────────────

- (void)filterWithQuery:(NSString *)query {
    [self applyFilter:query];
    if (_filtered.count == 0) { [self dismiss]; return; }
    [_table reloadData];
    [self selectFirst];
    if (self.isVisible) [self refit];
}

- (void)applyFilter:(NSString *)query {
    if (query.length == 0) { _filtered = allItems(); return; }
    NSMutableArray *out = [NSMutableArray new];
    SlashItem *pendingSep = nil;
    for (SlashItem *it in allItems()) {
        if (it.isSeparator) { pendingSep = it; continue; }
        if ([it.label rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            if (pendingSep && out.count) [out addObject:pendingSep];
            pendingSep = nil;
            [out addObject:it];
        }
    }
    _filtered = out;
}

- (void)refit {
    CGFloat h = kPadding * 2;
    for (SlashItem *it in _filtered) h += it.isSeparator ? kSepHeight : kRowHeight;
    h = MIN(h, kMaxHeight);
    NSRect f = _panel.frame;
    f.origin.y  += f.size.height - h;
    f.size.height = h;
    [_panel setFrame:f display:NO];
}

// ─── Keyboard navigation ─────────────────────────────────────────────────────

- (void)selectFirst {
    _selectedIndex = -1;
    for (NSInteger i = 0; i < (NSInteger)_filtered.count; i++) {
        if (!_filtered[i].isSeparator) { _selectedIndex = i; break; }
    }
    if (_selectedIndex >= 0)
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedIndex]
                byExtendingSelection:NO];
    else
        [_table deselectAll:nil];
}

- (void)moveUp {
    NSInteger i = _selectedIndex - 1;
    while (i >= 0 && _filtered[i].isSeparator) i--;
    if (i >= 0) { _selectedIndex = i; [self scrollTo:i]; }
}

- (void)moveDown {
    NSInteger i = _selectedIndex + 1;
    while (i < (NSInteger)_filtered.count && _filtered[i].isSeparator) i++;
    if (i < (NSInteger)_filtered.count) { _selectedIndex = i; [self scrollTo:i]; }
}

- (void)scrollTo:(NSInteger)row {
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_table scrollRowToVisible:row];
}

- (void)confirm {
    if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)_filtered.count) return;
    SlashItem *it = _filtered[_selectedIndex];
    if (it.isSeparator) return;
    [_delegate slashMenu:self didSelectPrefix:it.prefix suffix:it.suffix placeholder:it.placeholder];
}

- (void)rowClicked:(id)sender {
    NSInteger row = _table.clickedRow;
    if (row < 0 || row >= (NSInteger)_filtered.count || _filtered[row].isSeparator) return;
    _selectedIndex = row;
    [self confirm];
}

// ─── NSTableViewDataSource ────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_filtered.count;
}

// ─── NSTableViewDelegate ─────────────────────────────────────────────────────

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
    return _filtered[row].isSeparator ? kSepHeight : kRowHeight;
}

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    return !_filtered[row].isSeparator;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    SlashItem *it = _filtered[row];

    if (it.isSeparator) {
        NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, kSepHeight)];
        NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(10, 4, kPanelWidth - 20, 1)];
        line.boxType = NSBoxSeparator;
        [v addSubview:line];
        return v;
    }

    NSTableCellView *cell = [tv makeViewWithIdentifier:@"R" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, kRowHeight)];
        cell.identifier = @"R";
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.frame = NSMakeRect(14, 5, kPanelWidth - 24, 18);
        tf.autoresizingMask = NSViewWidthSizable;
        tf.font = [NSFont systemFontOfSize:13];
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:tf];
        cell.textField = tf;
    }
    cell.textField.stringValue = it.label;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    NSInteger row = _table.selectedRow;
    if (row >= 0 && row < (NSInteger)_filtered.count && !_filtered[row].isSeparator)
        _selectedIndex = row;
}

@end
