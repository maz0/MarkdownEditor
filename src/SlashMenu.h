#import <Cocoa/Cocoa.h>

@class SlashMenu;

@protocol SlashMenuDelegate <NSObject>
- (void)slashMenu:(SlashMenu *)menu
   didSelectPrefix:(NSString *)prefix
            suffix:(NSString *)suffix
       placeholder:(NSString *)placeholder;
- (void)slashMenuDidDismiss:(SlashMenu *)menu;
@end

@interface SlashMenu : NSObject
@property (nonatomic, weak) id<SlashMenuDelegate> delegate;
@property (nonatomic, readonly) BOOL isVisible;
- (void)showBelowRect:(NSRect)screenRect parentWindow:(NSWindow *)parent;
- (void)filterWithQuery:(NSString *)query;
- (void)moveUp;
- (void)moveDown;
- (void)confirm;
- (void)dismiss;
@end
