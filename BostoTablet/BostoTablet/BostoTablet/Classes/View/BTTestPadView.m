//
// Created by georgecook on 05/04/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import "BTTestPadView.h"
#import "Logging.h"

#define kBrushSize 30.0

@interface BTTestPadView ()
@property(nonatomic) NSPoint previousLocation;
@end

@implementation BTTestPadView
{

}

//////////////////////////////////////////////////////////////
#pragma mark lifecycle
//////////////////////////////////////////////////////////////

- (void)awakeFromNib
{
    [[self window] setAcceptsMouseMovedEvents:YES];
}

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    [self clearDisplay];
}


//////////////////////////////////////////////////////////////
#pragma mark mouse events 
//////////////////////////////////////////////////////////////

- (void)mouseDown:(NSEvent *)event
{
    [self logEvent:event];
    self.previousLocation = [self convertPoint:[event locationInWindow] fromView:nil];
}

- (void)mouseDragged:(NSEvent *)event
{
    BOOL isMouseDown = YES;
    while (isMouseDown)
    {
        event = [[self window] nextEventMatchingMask:NSLeftMouseUpMask |
                NSLeftMouseDraggedMask];

        switch ([event type])
        {
            case NSLeftMouseDragged:
                [self drawLineWithEvent:event];
                break;

            case NSLeftMouseUp:
                isMouseDown = NO;
                break;

            default:
                break;
        }
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    [self logEvent:event];
}

- (void)mouseUp:(NSEvent *)event
{
    [self logEvent:event];
}

- (void)logEvent:(NSEvent *)event
{
    NSPoint location = [event locationInWindow];

    float pressure = 0.0;
    // pressure: is not valid for MouseMove events
    if (event.type != NSMouseMoved)
    {
        pressure = event.pressure;
    }

    LogVerbose(@"Processed event with capabilities %d clickCount %d tanPressure %f buttonNumber %d buttonMask %d",
    event.capabilityMask,
    event.clickCount,
    event.tangentialPressure,
    event.buttonNumber,
    event.buttonMask);
    LogVerbose(@"Location %f,%f pressure: %f", location.x, location.y, pressure);
}




//////////////////////////////////////////////////////////////
#pragma mark private impl
//////////////////////////////////////////////////////////////



- (void)drawLineWithEvent:(NSEvent *)event
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSPoint location = [self convertPoint:[event locationInWindow]
                                 fromView:nil];
    float brushSize = kBrushSize * event.pressure;

    [self lockFocus];
    [[[NSColor blueColor] colorWithAlphaComponent:1.0] set];

    [path setLineWidth:brushSize];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path moveToPoint:self.previousLocation];
    [path lineToPoint:location];
    [path stroke];
    [self unlockFocus];

    [[self window] flushWindow];

    self.previousLocation = location;
}

//////////////////////////////////////////////////////////////
#pragma mark public api
//////////////////////////////////////////////////////////////

- (void)clearDisplay
{
    [self lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill([self bounds]);
    [self unlockFocus];
}

@end