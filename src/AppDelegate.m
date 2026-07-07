#import "AppDelegate.h"
#import "MDUpdateChecker.h"

@interface AppDelegate () <NSMenuDelegate>
@end

@implementation AppDelegate {
    MDUpdateChecker *_updateChecker;
    NSMenu          *_recentMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _updateChecker = [MDUpdateChecker new];  // before buildMenuBar: menu item targets it
    [self buildMenuBar];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"darkMode"])
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [_updateChecker checkAutomatically];
    // Don't manually open a new document here — applicationShouldOpenUntitledFile:
    // is called AFTER file-open Apple Events are processed, so it correctly
    // opens a blank doc only when the app wasn't launched by double-clicking a file.
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

// ─── Open Recent ─────────────────────────────────────────────────────────────
// NSDocumentController tracks recents automatically; a hand-built menu bar
// just doesn't get the standard submenu for free, so populate it on demand.

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _recentMenu) return;
    [menu removeAllItems];
    NSArray<NSURL *> *recents = [NSDocumentController sharedDocumentController].recentDocumentURLs;
    for (NSURL *url in recents) {
        NSMenuItem *item = [menu addItemWithTitle:url.lastPathComponent
                                           action:@selector(openRecentDocument:)
                                    keyEquivalent:@""];
        item.target            = self;
        item.representedObject = url;
        item.toolTip           = url.path;
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:url.path];
        icon.size = NSMakeSize(16, 16);
        item.image = icon;
    }
    if (recents.count) [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clear = [menu addItemWithTitle:@"Clear Menu"
                                        action:@selector(clearRecentDocuments:)
                                 keyEquivalent:@""];
    clear.enabled = recents.count > 0;
}

- (void)openRecentDocument:(NSMenuItem *)item {
    [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:item.representedObject
                              display:YES
                    completionHandler:^(NSDocument *doc, BOOL alreadyOpen, NSError *err) {
        if (err) [NSApp presentError:err];
    }];
}

- (void)newTab:(id)sender {
    NSError *err = nil;
    [[NSDocumentController sharedDocumentController] openUntitledDocumentAndDisplay:YES error:&err];
}

- (void)toggleDarkMode:(id)sender {
    NSAppearanceName name = NSApp.effectiveAppearance.name;
    BOOL isDark = [name isEqual:NSAppearanceNameDarkAqua] ||
                  [name isEqual:NSAppearanceNameAccessibilityHighContrastDarkAqua];
    NSApp.appearance = isDark
        ? [NSAppearance appearanceNamed:NSAppearanceNameAqua]
        : [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [[NSUserDefaults standardUserDefaults] setBool:!isDark forKey:@"darkMode"];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleDarkMode:)) {
        NSAppearanceName name = NSApp.effectiveAppearance.name;
        BOOL isDark = [name isEqual:NSAppearanceNameDarkAqua] ||
                      [name isEqual:NSAppearanceNameAccessibilityHighContrastDarkAqua];
        item.state = isDark ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

- (void)buildMenuBar {
    NSMenu *bar = [NSMenu new];

    // ── App ──────────────────────────────────────────────────────────────
    NSMenuItem *appItem = [NSMenuItem new];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"About Markdown Editor"
                       action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *updates = [appMenu addItemWithTitle:@"Check for Updates…"
                                             action:@selector(checkForUpdates:)
                                      keyEquivalent:@""];
    updates.target = _updateChecker;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Markdown Editor"
                       action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Markdown Editor"
                       action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [bar addItem:appItem];

    // ── File ─────────────────────────────────────────────────────────────
    NSMenuItem *fileItem = [NSMenuItem new];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New"      action:@selector(newDocument:)     keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"New Tab"  action:@selector(newTab:) keyEquivalent:@"t"];
    [fileMenu addItemWithTitle:@"Open…"   action:@selector(openDocument:)    keyEquivalent:@"o"];
    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent"
                                                 action:nil keyEquivalent:@""];
    _recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    _recentMenu.delegate = self; // populated on demand in menuNeedsUpdate:
    recentItem.submenu = _recentMenu;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close"        action:@selector(performClose:)          keyEquivalent:@"w"];
    [fileMenu addItemWithTitle:@"Save"         action:@selector(saveDocument:)          keyEquivalent:@"s"];
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Save As…"
                                             action:@selector(saveDocumentAs:) keyEquivalent:@"s"];
    saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *rename = [fileMenu addItemWithTitle:@"Rename…"
                                                action:@selector(beginRename:)
                                         keyEquivalent:@"r"];
    rename.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItemWithTitle:@"Revert to Saved"
                        action:@selector(revertDocumentToSaved:) keyEquivalent:@""];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Export as HTML…" action:@selector(exportHTML:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Export as PDF…"  action:@selector(exportPDF:)  keyEquivalent:@""];
    fileItem.submenu = fileMenu;
    [bar addItem:fileItem];

    // ── Edit ─────────────────────────────────────────────────────────────
    NSMenuItem *editItem = [NSMenuItem new];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut"        action:@selector(cut:)       keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"       action:@selector(copy:)      keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"      action:@selector(paste:)     keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find…" action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
    NSMenuItem *findNext = [editMenu addItemWithTitle:@"Find Next"
                                               action:@selector(performFindPanelAction:) keyEquivalent:@"g"];
    findNext.tag = NSFindPanelActionNext;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Bold"   action:@selector(mdBold:)   keyEquivalent:@"b"];
    [editMenu addItemWithTitle:@"Italic" action:@selector(mdItalic:) keyEquivalent:@"i"];
    [editMenu addItemWithTitle:@"Link"   action:@selector(mdLink:)   keyEquivalent:@"k"];
    editItem.submenu = editMenu;
    [bar addItem:editItem];

    // ── Format ───────────────────────────────────────────────────────────
    NSMenuItem *fmtItem = [NSMenuItem new];
    NSMenu *fmtMenu = [[NSMenu alloc] initWithTitle:@"Format"];
    NSMenuItem *incFont = [fmtMenu addItemWithTitle:@"Increase Font Size"
                                             action:@selector(increaseFontSize:)
                                      keyEquivalent:@"+"];
    incFont.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSMenuItem *decFont = [fmtMenu addItemWithTitle:@"Decrease Font Size"
                                             action:@selector(decreaseFontSize:)
                                      keyEquivalent:@"-"];
    decFont.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSMenuItem *resetFont = [fmtMenu addItemWithTitle:@"Reset Font Size"
                                               action:@selector(resetFontSize:)
                                        keyEquivalent:@"0"];
    resetFont.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    fmtItem.submenu = fmtMenu;
    [bar addItem:fmtItem];

    // ── View ─────────────────────────────────────────────────────────────
    NSMenuItem *viewItem = [NSMenuItem new];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Show Tab Bar" action:@selector(toggleTabBar:) keyEquivalent:@""];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *focusItem = [viewMenu addItemWithTitle:@"Focus Mode"
                                                action:@selector(toggleFocusMode:)
                                         keyEquivalent:@"f"];
    focusItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *previewItem = [viewMenu addItemWithTitle:@"Preview"
                                                  action:@selector(togglePreview:)
                                           keyEquivalent:@"p"];
    previewItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *outlineItem = [viewMenu addItemWithTitle:@"Outline"
                                                  action:@selector(toggleOutline:)
                                           keyEquivalent:@"o"];
    outlineItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Dark Appearance" action:@selector(toggleDarkMode:) keyEquivalent:@""];
    viewItem.submenu = viewMenu;
    [bar addItem:viewItem];

    // ── Window ───────────────────────────────────────────────────────────
    NSMenuItem *winItem = [NSMenuItem new];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [winMenu addItemWithTitle:@"Minimize"        action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Zoom"            action:@selector(performZoom:)        keyEquivalent:@""];
    [winMenu addItem:[NSMenuItem separatorItem]];
    [winMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    winItem.submenu = winMenu;
    [bar addItem:winItem];
    [NSApp setWindowsMenu:winMenu];

    [NSApp setMainMenu:bar];
}

@end
