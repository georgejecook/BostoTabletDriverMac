//
// Created by georgecook on 05/04/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import "BTCustomCursorButton.h"


@implementation BTCustomCursorButton
- (void)resetCursorRects
{
    if (self.cursor) {
        [self addCursorRect:[self bounds] cursor:self.cursor];
    } else {
        [super resetCursorRects];
    }
}
@end