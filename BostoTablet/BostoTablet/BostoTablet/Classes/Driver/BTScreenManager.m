/*
 (c) George Cook 2013
 --
 Based on Udo Killerman's Hyperpen-for-apple project http://code.google.com/p/hyperpen-for-apple/
 Tablet State and Event Processing taken in major parts from
 Tablet Magic Daemon Sources (c) 2011 Thinkyhead Software

 Aiptek Report Decoding and Command Codes taken from Linux 2.6
 Kernel Driver aiptek.c
 --
 Copyright (c) 2001      Chris Atenasio   <chris@crud.net>
 Copyright (c) 2002-2004 Bryan W. Headley <bwheadley@earthlink.net>

 based on wacom.c by
 Vojtech Pavlik      <vojtech@suse.cz>
 Andreas Bach Aaen   <abach@stofanet.dk>
 Clifford Wolf       <clifford@clifford.at>
 Sam Mosel           <sam.mosel@computer.org>
 James E. Blair      <corvus@gnu.org>
 Daniel Egger        <egger@suse.de>
 --

 LICENSE

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU Library General Public
 License as published by the Free Software Foundation; either
 version 3 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Library General Public License for more details.

 You should have received a copy of the GNU Library General Public
 License along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/
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