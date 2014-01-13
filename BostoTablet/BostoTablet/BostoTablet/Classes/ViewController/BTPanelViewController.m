#import "BTPanelViewController.h"
#import "BTBackgroundView.h"
#import "BTStatusItemView.h"
#import "BTMenubarController.h"
#import "BTScreenManager.h"
#import "BTDriverManager.h"
#import "BTTestPadView.h"
#import "BTCustomCursorButton.h"
#import "NSScreen+BTAdditions.h"
#import "STPrivilegedTask.h"

#define OPEN_DURATION .15
#define CLOSE_DURATION .1

#define SEARCH_INSET 17

#define POPUP_HEIGHT 368
#define PANEL_WIDTH 449
#define MENU_ANIMATION_DURATION .1


@interface BTPanelViewController ()
@property(nonatomic, strong) NSTimer *cursorUpdateTimer;
@property(nonatomic) int cursorMoveAction;
@end

@implementation BTPanelViewController
{
    BOOL _hasActivePanel;
    id _eventMonitor;
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
        [self addDebugKeyHandler];
    }
    return self;
}

- (void)addDebugKeyHandler
{
    _eventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
                                     (NSLeftMouseDownMask | NSRightMouseDownMask | NSOtherMouseDownMask | NSKeyDownMask)
                                                           handler:^void(NSEvent *incomingEvent) {
                                                               NSEvent *result = incomingEvent;
                                                               NSWindow *targetWindowForEvent = [incomingEvent window];

                                                               if ([incomingEvent type] == NSKeyDown)
                                                               {
                                                                   if ([incomingEvent keyCode] == 53)
                                                                   {
                                                                       // when we press escape we send a mouse up event to be safe
                                                                       [[BTDriverManager shared]
                                                                                         sendMouseUpEventToUnblockTheMouse];
                                                                   }
                                                               }
                                                           }];
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
    self.smoothingSlider.intValue = [BTDriverManager shared].smoothingLevel;

    self.georgeButton.cursor = [NSCursor pointingHandCursor];
    self.githubLinkButton.cursor = [NSCursor pointingHandCursor];
    self.refreshButton.cursor = [NSCursor pointingHandCursor];
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
    panelRect.size.height = POPUP_HEIGHT;
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

- (IBAction)didChangeSmoothingSlider:(id)sender
{
    [BTDriverManager shared].smoothingLevel = self.smoothingSlider.intValue;
}


- (IBAction)didClickClearTestPad:(id)sender
{
    [self.testPadView clearDisplay];
}

- (IBAction)didClickGithubHyperlink:(id)sender
{
    [[NSWorkspace sharedWorkspace]
                  openURL:[[NSURL alloc] initWithString:@"https://github.com/georgejecook/BostoTabletDriverMac"]];
    self.hasActivePanel = NO;
}

- (IBAction)didClickRefresh:(id)sender
{
    [[BTDriverManager shared] reinitialize];
}

- (IBAction)didClickQuit:(id)sender
{
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

- (IBAction)didClickGeorge:(id)sender
{
    [[NSWorkspace sharedWorkspace]
                  openURL:[[NSURL alloc] initWithString:@"http://bo.linkedin.com/in/georgejecook"]];
    self.hasActivePanel = NO;

}

- (IBAction)didClickCusrorButton:(id)sender
{
    NSButton *button = sender;
    [self updateCursorPositionWithIndex:button.tag];
}

- (void)updateCursorPositionWithIndex:(int)index{
    CGPoint currentCursor = [BTDriverManager shared].cursorOffset;
    switch (index)
       {
           case 1:
               NSLog(@"moving cursor up");
               currentCursor.y -= 1;
               break;
           case 2:
               NSLog(@"moving cursor right");
               currentCursor.x += 1;
               break;
           case 3:
               NSLog(@"moving cursor down");
               currentCursor.y += 1;
               break;
           case 4:
               NSLog(@"moving cursor left");
               currentCursor.x -= 1;
               break;
           case 5:
               currentCursor.x = 0;
               currentCursor.y = 0;
               break;
           default:
               break;
       }
       [BTDriverManager shared].cursorOffset = currentCursor;
}
- (void)keyDown:(NSEvent *)theEvent
{
    [super keyDown:theEvent];
    switch( [theEvent keyCode] ) {
           case 126:       // up arrow
               self.cursorMoveAction = 1;
               break;
           case 125:       // down arrow
               self.cursorMoveAction = 3;
               break;
           case 124:       // right arrow
               self.cursorMoveAction = 2;
               break;
           case 123:       // left arrow
               self.cursorMoveAction = 4;
               break;
           default:
               break;
       }

    self.cursorUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.3f
                                                            target:self
                                                          selector:@selector(timerDidFire:)
                                                          userInfo:nil
                                                           repeats:YES]; 

    [self updateCursorPositionWithIndex:self.cursorMoveAction];
}

- (void)keyUp:(NSEvent *)theEvent
{
    [super keyUp:theEvent];
    self.cursorUpdateTimer = nil;
}

- (void)setCursorUpdateTimer:(NSTimer *)cursorUpdateTimer
{
    [_cursorUpdateTimer invalidate];
    _cursorUpdateTimer = cursorUpdateTimer;
}


- (IBAction)didClickImproveSpeed:(id)sender
{


    int pid = [[NSProcessInfo processInfo] processIdentifier];
    NSArray *arguments = @[@"renice", @"-20", @"-p", [NSString stringWithFormat:@"%d", pid]];
    STPrivilegedTask *task = [[STPrivilegedTask alloc]
                                                initWithLaunchPath:@"/usr/bin/sudo" arguments:arguments];
    [task launch];
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
    NSString *screenName = [screen screenName];
    return [NSString stringWithFormat:@"%@ %@ ", screenName ? screenName : screenNumber, NSStringFromSize(screenSize)];
}

//////////////////////////////////////////////////////////////
#pragma mark notifications 
//////////////////////////////////////////////////////////////

- (void)didChangeDriverStatus:(id)didChangeScreenDetails
{
    self.statusLabel.stringValue = [BTDriverManager shared].isConnected ? @"Connected" : @"Not Connected";
    CGPoint cursorOffset = [BTDriverManager shared].cursorOffset;
    self.cursorLabel.stringValue = [NSString stringWithFormat:@"Offset %.0f,%.0f", cursorOffset.x, cursorOffset.y];
}

- (void)didChangeScreenDetails:(id)didChangeScreenDetails
{
    [self.displaysCombo reloadData];
    NSScreen *targetScreen = [BTScreenManager shared].targetScreen;
    if (targetScreen)
    {
        NSInteger index = [[NSScreen screens] indexOfObject:targetScreen];
        [self.displaysCombo selectItemAtIndex:index];
    } else
    {
        [self.displaysCombo deselectItemAtIndex:self.displaysCombo.indexOfSelectedItem];
    }
}

//////////////////////////////////////////////////////////////
#pragma mark private impl
//////////////////////////////////////////////////////////////

@end
