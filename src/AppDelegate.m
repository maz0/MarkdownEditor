#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildMenuBar];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"darkMode"])
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
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
