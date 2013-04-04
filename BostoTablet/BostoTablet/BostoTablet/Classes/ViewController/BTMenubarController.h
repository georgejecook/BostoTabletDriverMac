#define STATUS_ITEM_VIEW_WIDTH 24.0

#pragma mark -

@class BTStatusItemView;

@interface BTMenubarController : NSObject {
@private
    BTStatusItemView *_statusItemView;
}

@property (nonatomic) BOOL hasActiveIcon;
@property (nonatomic, strong, readonly) NSStatusItem *statusItem;
@property (nonatomic, strong, readonly) BTStatusItemView *statusItemView;

@end
