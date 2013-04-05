//
// Created by georgecook on 05/04/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import "CustomCursorButton.h"


@implementation CustomCursorButton
- (void)resetCursorRects
{
    if (self.cursor) {
        [self addCursorRect:[self bounds] cursor:self.cursor];
    } else {
        [super resetCursorRects];
    }
}
@end