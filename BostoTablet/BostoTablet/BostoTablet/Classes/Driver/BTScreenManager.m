//
// Created by georgecook on 16/03/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import "BTScreenManager.h"


@interface BTScreenManager ()
@end

@implementation BTScreenManager
{

}

//////////////////////////////////////////////////////////////
#pragma mark public api
//////////////////////////////////////////////////////////////

- (CGPoint)mapTabletCoordinatesToDisplaySpaceWithPoint:(CGPoint)point toTabletMapping:(CGRect)tabletMapping{
    CGFloat swide = _screenMapping.size.width, shigh = _screenMapping.size.height,
            twide = tabletMapping.size.width, thigh = tabletMapping.size.height;

    CGFloat sx1 = _screenMapping.origin.x,
            sy1 = _screenMapping.origin.y;

    // And the Tablet Boundary
    //
    CGFloat nx, ny,
            tx1 = tabletMapping.origin.x,
            tx2 = tx1 + twide - 1,
            ty1 = tabletMapping.origin.y,
            ty2 = ty1 + thigh - 1;


    // Get the ratio of the screen to the tablet
    CGFloat hratio = swide / twide, vratio = shigh / thigh;

    // Constrain the stylus to the active tablet area
    CGFloat x = point.x, y = point.y;

    if (x < tx1) x = tx1;
    if (x > tx2) x = tx2;
    if (y < ty1) y = ty1;
    if (y > ty2) y = ty2;

    // Map the Stylus Point to the active Screen Area
    nx = (sx1 + (x - tx1) * hratio);
    ny = (sy1 + (y - ty1) * vratio);

    return CGPointMake(nx + _screenBounds.origin.x, ny + _screenBounds.origin.y);
}

- (void)updateDisplaysBoundsWithDisplayId:(int)displayID {
    //	CGRect				activeDisplaysBounds;
    CGDirectDisplayID *displays;
    CGDisplayCount numDisplays;
    CGDisplayCount i;
    CGDisplayErr err;
    bool result = false;

    //TODO - we need to find the location of the monitor screen in multi screen setups

    self.screenBounds = CGRectMake(0.0, 0.0, 0.0, 0.0);

    err = CGGetActiveDisplayList(0, NULL, &numDisplays);

    if (err == CGDisplayNoErr && numDisplays > 0)
    {
        displays = (CGDirectDisplayID *) malloc(numDisplays * sizeof(CGDirectDisplayID));

        if (NULL != displays)
        {
            err = CGGetActiveDisplayList(numDisplays, displays, &numDisplays);

            if (err == CGDisplayNoErr)
            {

                if (displayID == -1 || numDisplays < displayID)
                {
                    for (i = 0; i < numDisplays; i++)
                        self.screenBounds = CGRectUnion(self.screenBounds, CGDisplayBounds(displays[i]));
                }
                else
                {
                    self.screenBounds = CGDisplayBounds(displays[displayID]);
                }
            }


            free(displays);
            result = true;
        }
    }

    exit:
    NSLog(@"Screen Boundary: %.2f, %.2f - %.2f, %.2f\n", self.screenBounds.origin.x, self.screenBounds.origin.y,
            self.screenBounds.size.width, self.screenBounds.size.height);
}

-(void)setScreenMapping:(CGRect )value
{
    SInt16 mappedWidth;
    SInt16 mappedHeight;

    if (value.origin.x == -1)
    {
        value.origin.x = 0;
    }

    if (value.origin.y == -1)
    {
        value.origin.y = 0;
    }

    if (value.size.width == -1)
    {
        if (value.origin.x < 0)
        {
            mappedWidth = abs(value.origin.x);
        }
        else
        {
            mappedWidth = self.screenBounds.size.width - value.origin.x;
        }
    }
    else
    {
        if (value.origin.x < 0)
        {
            mappedWidth = abs(value.origin.x);
        }
        else
        {
            mappedWidth = value.size.width - value.origin.x;
        }
    }

    if (value.size.height == -1)
    {
        if (value.origin.y < 0)
        {
            mappedHeight = value.size.height;
        }
        else
        {
            mappedHeight = self.screenBounds.size.height - value.size.height;
        }
    }
    else
    {
        if (value.origin.y < 0)
        {
            mappedHeight = value.size.height;
        }
        else
        {
            mappedHeight = value.size.height - value.origin.y;
        }
    }


    _screenMapping = CGRectMake(
            value.origin.x, value.origin.y,
            mappedWidth,
            mappedHeight
    );

    NSLog(@"Updated Screen Mapping: %.2f, %.2f - %.2f, %.2f\n", _screenMapping.origin.x, _screenMapping.origin.y,
    _screenMapping.size.width, _screenMapping.size.height);
}

@end