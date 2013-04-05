#import "BTPanelViewController.h"
#import "BTBackgroundView.h"
#import "BTStatusItemView.h"
#import "BTMenubarController.h"
#import "BTScreenManager.h"
#import "BTDriverManager.h"
#import "BTTestPadView.h"

#define OPEN_DURATION .15
#define CLOSE_DURATION .1

#define SEARCH_INSET 17

#define POPUP_HEIGHT 368
#define PANEL_WIDTH 449
#define MENU_ANIMATION_DURATION .1

#pragma mark -

@implementation BTPanelViewController
{
    BOOL _hasActivePanel;
}

@synthesize backgroundView = _backgroundView;
@synthesize delegate = _delegate;

//////////////////////////////////////////////////////////////
#pragma mark lifecycle
//////////////////////////////////////////////////////////////

- (id)initWithDelegate:(id <PanelControllerDelegate>)delegate
{
    self = [super initWithWindowNibName:@"Panel"];
    if (self != nil)
    {
        _delegate = delegate;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector (didChangeScreenDetails:)
                                                     name:kBTScreenManagerDidChangeScreenDetails
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector (didChangeDriverStatus:)
                                                     name:kBTDriverManagerDidChangeStatus
                                                   object:nil];

    }
    return self;
}

- (void)didChangeScreenParameters:(id)didChangeScreenParameters
{
    [self.displaysCombo reloadData];
    //self.displaysCombo.indexOfSelectedItem = 1;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]
                           removeObserver:self name:kBTScreenManagerDidChangeScreenDetails object:nil];
    [[NSNotificationCenter defaultCenter]
                           removeObserver:self name:kBTDriverManagerDidChangeStatus object:nil];
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    // Make a fully skinned panel
    NSPanel *panel = (id) [self window];
    [panel setAcceptsMouseMovedEvents:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];

    // Resize panel
    NSRect panelRect = [[self window] frame];
    panelRect.size.height = POPUP_HEIGHT;
    [[self window] setFrame:panelRect display:NO];

    self.displaysCombo.dataSource = self;
    self.displaysCombo.delegate = self;
    [self didChangeScreenDetails:nil];
    [self didChangeDriverStatus:nil];

    self.pressureSlider.floatValue = [BTDriverManager shared].pressureDamping;
}

//////////////////////////////////////////////////////////////
#pragma mark public accessors
//////////////////////////////////////////////////////////////



- (BOOL)hasActivePanel
{
    return _hasActivePanel;
}

- (void)setHasActivePanel:(BOOL)flag
{
    if (_hasActivePanel != flag)
    {
        _hasActivePanel = flag;

        if (_hasActivePanel)
        {
            [self openPanel];
        }
        else
        {
            [self closePanel];
        }
    }
}

//////////////////////////////////////////////////////////////
#pragma mark NSWindowDelegate impl
//////////////////////////////////////////////////////////////

- (void)windowWillClose:(NSNotification *)notification
{
    self.hasActivePanel = NO;
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    if ([[self window] isVisible])
    {
        self.hasActivePanel = NO;
    }
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *panel = [self window];
    NSRect statusRect = [self statusRectForWindow:panel];
    NSRect panelRect = [panel frame];

    CGFloat statusX = roundf(NSMidX(statusRect));
    CGFloat panelX = statusX - NSMinX(panelRect);

    self.backgroundView.arrowX = panelX;
}

//////////////////////////////////////////////////////////////
#pragma mark keyboard
//////////////////////////////////////////////////////////////

- (void)cancelOperation:(id)sender
{
    self.hasActivePanel = NO;
}

//////////////////////////////////////////////////////////////
#pragma mark public api
//////////////////////////////////////////////////////////////

- (NSRect)statusRectForWindow:(NSWindow *)window
{
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = NSZeroRect;

    BTStatusItemView *statusItemView = nil;
    if ([self.delegate respondsToSelector:@selector(statusItemViewForPanelController:)])
    {
        statusItemView = [self.delegate statusItemViewForPanelController:self];
    }

    if (statusItemView)
    {
        statusRect = statusItemView.globalRect;
        statusRect.origin.y = NSMinY(statusRect) - NSHeight(statusRect);
    }
    else
    {
        statusRect.size = NSMakeSize(STATUS_ITEM_VIEW_WIDTH, [[NSStatusBar systemStatusBar] thickness]);
        statusRect.origin.x = roundf((NSWidth(screenRect) - NSWidth(statusRect)) / 2);
        statusRect.origin.y = NSHeight(screenRect) - NSHeight(statusRect) * 2;
    }
    return statusRect;
}

- (void)openPanel
{
    NSWindow *panel = [self window];

    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = [self statusRectForWindow:panel];

    NSRect panelRect = [panel frame];
    panelRect.size.width = PANEL_WIDTH;
    panelRect.origin.x = roundf(NSMidX(statusRect) - NSWidth(panelRect) / 2);
    panelRect.origin.y = NSMaxY(statusRect) - NSHeight(panelRect);

    if (NSMaxX(panelRect) > (NSMaxX(screenRect) - ARROW_HEIGHT))
        panelRect.origin.x -= NSMaxX(panelRect) - (NSMaxX(screenRect) - ARROW_HEIGHT);

    [NSApp activateIgnoringOtherApps:NO];
    [panel setAlphaValue:0];
    [panel setFrame:statusRect display:YES];
    [panel makeKeyAndOrderFront:nil];

    NSTimeInterval openDuration = OPEN_DURATION;

    NSEvent *currentEvent = [NSApp currentEvent];
    if ([currentEvent type] == NSLeftMouseDown)
    {
        NSUInteger clearFlags = ([currentEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask);
        BOOL shiftPressed = (clearFlags == NSShiftKeyMask);
        BOOL shiftOptionPressed = (clearFlags == (NSShiftKeyMask | NSAlternateKeyMask));
        if (shiftPressed || shiftOptionPressed)
        {
            openDuration *= 10;

            if (shiftOptionPressed)
                NSLog(@"Icon is at %@\n\tMenu is on screen %@\n\tWill be animated to %@",
                        NSStringFromRect(statusRect), NSStringFromRect(screenRect), NSStringFromRect(panelRect));
        }
    }

    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:openDuration];
    [[panel animator] setFrame:panelRect display:YES];
    [[panel animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
}

- (void)closePanel
{
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:CLOSE_DURATION];
    [[[self window] animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];

    dispatch_after(dispatch_walltime(NULL, NSEC_PER_SEC * CLOSE_DURATION * 2), dispatch_get_main_queue(), ^{

        [self.window orderOut:nil];
    });
}

//////////////////////////////////////////////////////////////
#pragma mark actions
//////////////////////////////////////////////////////////////

- (IBAction)didChangePressureSlider:(id)sender
{
    [BTDriverManager shared].pressureDamping = self.pressureSlider.floatValue;
}

- (IBAction)didClickClearTestPad:(id)sender
{
    [self.testPadView clearDisplay];
}


//////////////////////////////////////////////////////////////
#pragma mark combobox delegate methods
//////////////////////////////////////////////////////////////

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    //TODO -set the screenmanager
    NSScreen *screen = [[NSScreen screens] objectAtIndex:[self.displaysCombo indexOfSelectedItem]];
    [BTScreenManager shared].targetScreen = screen;
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
    return [NSScreen screens].count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
    NSScreen *screen = [NSScreen screens][index];
    NSSize screenSize = [screen.deviceDescription[@"NSDeviceSize"] sizeValue];

    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    return [NSString stringWithFormat:@"%@ (id:%@)", NSStringFromSize(screenSize), screenNumber];
}

//////////////////////////////////////////////////////////////
#pragma mark notifications 
//////////////////////////////////////////////////////////////

- (void)didChangeDriverStatus:(id)didChangeScreenDetails{
    self.statusLabel.stringValue = [BTDriverManager shared].isConnected ? @"Connected" : @"Not Connected";
}

- (void)didChangeScreenDetails:(id)didChangeScreenDetails
{
    [self.displaysCombo reloadData];
    NSScreen *targetScreen = [BTScreenManager shared].targetScreen;
    if (targetScreen)
    {
        NSInteger index = [[NSScreen screens] indexOfObject:targetScreen];
        [self.displaysCombo selectItemAtIndex:index];
    } else {
        [self.displaysCombo deselectItemAtIndex:self.displaysCombo.indexOfSelectedItem];
    }
}


@end
