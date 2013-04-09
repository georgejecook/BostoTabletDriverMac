#import "BTBackgroundView.h"
#import "BTStatusItemView.h"

@class BTPanelViewController;
@class BTTestPadView;
@class BTCustomCursorButton;

@protocol PanelControllerDelegate <NSObject>

@optional

- (BTStatusItemView *)statusItemViewForPanelController:(BTPanelViewController *)controller;

@end

#pragma mark -

@interface BTPanelViewController : NSWindowController <NSWindowDelegate, NSComboBoxDelegate, NSComboBoxDataSource>
{
}

@property(nonatomic, weak) IBOutlet BTBackgroundView *backgroundView;
@property(nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property(nonatomic, weak) IBOutlet NSTextField *cursorLabel;
@property(nonatomic, weak) IBOutlet NSComboBox *displaysCombo;
@property(nonatomic, weak) IBOutlet NSSlider *pressureSlider;
@property(nonatomic, weak) IBOutlet BTTestPadView *testPadView;
@property(nonatomic, weak) IBOutlet BTCustomCursorButton *refreshButton;
@property(nonatomic, weak) IBOutlet BTCustomCursorButton *georgeButton;
@property(nonatomic, weak) IBOutlet BTCustomCursorButton *githubLinkButton;

@property(nonatomic) BOOL hasActivePanel;
@property(nonatomic, weak, readonly) id <PanelControllerDelegate> delegate;

- (id)initWithDelegate:(id <PanelControllerDelegate>)delegate;

- (void)openPanel;

- (void)closePanel;

- (IBAction)didChangePressureSlider:(id)sender;

- (IBAction)didClickClearTestPad:(id)sender;

- (IBAction)didClickGithubHyperlink:(id)sender;

- (IBAction)didClickRefresh:(id)sender;

- (IBAction)didClickQuit:(id)sender;

- (IBAction)didClickGeorge:(id)sender;

- (IBAction)didClickCusrorButton:(id)sender;
@end
