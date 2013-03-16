//
// Created by georgecook on 16/03/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import <Foundation/Foundation.h>


@interface BTScreenManager : NSObject

@property(nonatomic, assign) CGRect screenMapping;
@property(nonatomic) CGRect screenBounds;

- (CGPoint)mapTabletCoordinatesToDisplaySpaceWithPoint:(CGPoint)point toTabletMapping:(CGRect)tabletMapping;

/**
* pass -1 to use the tablet on ALL displays,
* or pass the displayID of the tablet to just use that display
*/
- (void)updateDisplaysBoundsWithDisplayId:(int)displayID;
@end