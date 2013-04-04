#import "BTBackgroundView.h"
#import "BTStatusItemView.h"

@class BTPanelViewController;

@protocol PanelControllerDelegate <NSObject>

@optional

- (BTStatusItemView *)statusItemViewForPanelController:(BTPanelViewController *)controller;

@end

#pragma mark -

@interface BTPanelViewController : NSWindowController <NSWindowDelegate>
{
}

@property (nonatomic, weak) IBOutlet BTBackgroundView *backgroundView;

@property (nonatomic) BOOL hasActivePanel;
@property (nonatomic, weak, readonly) id<PanelControllerDelegate> delegate;

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate;

- (void)openPanel;
- (void)closePanel;

@end
