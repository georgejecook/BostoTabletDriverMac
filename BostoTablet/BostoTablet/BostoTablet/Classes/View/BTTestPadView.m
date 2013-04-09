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
@property(nonatomic) BOOL isActive;
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
    self.isActive = YES;
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
    if (!self.isActive)
    {
        return;
    }
    [self logEvent:event withType:@"DOWN"];
    self.previousLocation = [self convertPoint:[event locationInWindow] fromView:nil];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!self.isActive)
    {
        return;
    }
    [self logEvent:event withType:@"DRAGGED"];
    BOOL isMouseDown = YES;
    while (isMouseDown)
    {
        event = [[self window] nextEventMatchingMask:NSLeftMouseUpMask |
                NSLeftMouseDraggedMask];

        switch ([event type])
        {
            case NSLeftMouseDragged:
                [self logEvent:event withType:@"DRAGGED-LOOP"];
                [self drawLineWithEvent:event];
                break;

            case NSLeftMouseUp:
                [self logEvent:event withType:@"DOWN-LOOP"];
                isMouseDown = NO;
                break;

            default:
                break;
        }
    }
}

- (void)mouseEntered:(NSEvent *)theEvent
{
    [self logEvent:theEvent withType:@"entered"];
}

- (void)mouseExited:(NSEvent *)theEvent
{
    [self logEvent:theEvent withType:@"exited"];

}


- (void)mouseMoved:(NSEvent *)event
{
    if (!self.isActive)
    {
        return;
    }
    [self logEvent:event withType:@"Move"];
}

- (void)mouseUp:(NSEvent *)event
{
    if (!self.isActive)
    {
        return;
    }
    [self logEvent:event withType:@"UP"];
}

- (void)logEvent:(NSEvent *)event withType:(NSString *)typeName
{
    NSPoint location = [event locationInWindow];

    float pressure = 0.0;
    // pressure: is not valid for MouseMove events
    if (event.type != NSMouseMoved)
    {
        pressure = event.pressure;
    }

    LogInfo(@"[%@] cap %d cc %d pres %f bn %d bm %d",
    typeName,
    event.capabilityMask,
    event.clickCount,
    event.pressure,
    event.buttonNumber,
    event.buttonMask);
//    LogVerbose(@"Location %f,%f pressure: %f", location.x, location.y, pressure);
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
    [[[NSColor blueColor] colorWithAlphaComponent:0.1 + (0.4 * event.pressure)] set];

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