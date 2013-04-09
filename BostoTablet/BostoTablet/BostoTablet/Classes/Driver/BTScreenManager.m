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
#import "BTMacros.h"


NSString *const kBTScreenManagerDidChangeScreenDetails = @"BTScreenManagerDidChangeScreenDetails";

@interface BTScreenManager ()
@end

@implementation BTScreenManager
{

}
//////////////////////////////////////////////////////////////
#pragma mark - singleton impl
//////////////////////////////////////////////////////////////

+ (BTScreenManager *)shared
{
    DEFINE_SHARED_INSTANCE_USING_BLOCK(^{
        return [[self alloc] init];
    });
}



//////////////////////////////////////////////////////////////
#pragma mark lifecycle
//////////////////////////////////////////////////////////////

- (id)init
{
    self = [super init];
    if (self)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector (didChangeScreenParameters:)
                                                     name:NSApplicationDidChangeScreenParametersNotification
                                                   object:nil];

        //TODO look in the defaults to see if there is one saved..
        self.targetScreen = [self bestScreenToUseAsTargetScreen];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]
            removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
}

//////////////////////////////////////////////////////////////
#pragma mark actions
//////////////////////////////////////////////////////////////

- (void)didChangeScreenParameters:(id)didChangeScreenParameters
{
    if (self.targetScreen != nil && ![[NSScreen screens] containsObject:self.targetScreen]){
        self.targetScreen = [self bestScreenToUseAsTargetScreen];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kBTScreenManagerDidChangeScreenDetails object:self];
}

//////////////////////////////////////////////////////////////
#pragma mark public accessors
//////////////////////////////////////////////////////////////

- (void)setTargetScreen:(NSScreen *)targetScreen
{
    _targetScreen = targetScreen;
    NSSize screenSize = [targetScreen.deviceDescription[@"NSDeviceSize"] sizeValue];
    self.screenBounds = CGRectMake(targetScreen.frame.origin.x, targetScreen.frame.origin.y, screenSize.width, screenSize.height);
    [[NSNotificationCenter defaultCenter] postNotificationName:kBTScreenManagerDidChangeScreenDetails object:self];
}

//////////////////////////////////////////////////////////////
#pragma mark private impl
//////////////////////////////////////////////////////////////

- (NSScreen *)bestScreenToUseAsTargetScreen
{
    //TODO find a way to identify the bosto screen - for now assuming it's not the main display in a multi display setup
    //if more than one display is present, we might have to do something else...
    if ([NSScreen screens].count == 1){
        return [NSScreen mainScreen];
    }

#warning - hard coded to main screen for now as I'm debugging without the screen connected
    return [NSScreen mainScreen];

    for (NSScreen *screen in [NSScreen screens]){
        //TODO - check the screen name
        if (screen != [NSScreen mainScreen]) {
            return screen;
        }
    }
    return nil;
}


//////////////////////////////////////////////////////////////
#pragma mark public api
//////////////////////////////////////////////////////////////

- (CGRect)mapTabletCoordinatesToDisplaySpaceWithPoint:(CGPoint)point toTabletMapping:(CGRect)tabletMapping
{
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

    return CGRectMake(nx + _screenBounds.origin.x, ny + _screenBounds.origin.y, (UInt8)((nx-(int)nx)*256), (UInt8)((ny-(int)ny)*256));
}

- (void)setScreenMapping:(CGRect)value
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