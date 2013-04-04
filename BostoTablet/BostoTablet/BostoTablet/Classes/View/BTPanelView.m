#import "BTPanelView.h"

@implementation BTPanelView

- (BOOL)canBecomeKeyWindow;
{
    return YES; // Allow Search field to become the first responder
}

@end
