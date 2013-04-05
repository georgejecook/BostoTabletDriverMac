#import "BTBackgroundView.h"
#import "BTStatusItemView.h"

@class BTPanelViewController;
@class BTTestPadView;

@protocol PanelControllerDelegate <NSObject>

@optional

- (BTStatusItemView *)statusItemViewForPanelController:(BTPanelViewController *)controller;

@end

#pragma mark -

@interface BTPanelViewController : NSWindowController <NSWindowDelegate, NSComboBoxDelegate, NSComboBoxDataSource>
{
}

@property (nonatomic, weak) IBOutlet BTBackgroundView *backgroundView;
@property(nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property(nonatomic, weak) IBOutlet NSComboBox *displaysCombo;
@property(nonatomic, weak) IBOutlet NSSlider *pressureSlider;
@property(nonatomic, weak) IBOutlet BTTestPadView *testPadView;

@property (nonatomic) BOOL hasActivePanel;
@property (nonatomic, weak, readonly) id<PanelControllerDelegate> delegate;

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate;

- (void)openPanel;
- (void)closePanel;

- (IBAction)didChangePressureSlider:(id)sender;
- (IBAction)didClickClearTestPad:(id)sender;

@end
