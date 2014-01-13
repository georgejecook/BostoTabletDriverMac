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
#import "BTDriverManager.h"
#import "BTMacros.h"
#import "stylus.h"
#import "BTScreenManager.h"
#import "Logging.h"
#import "Wacom.h"

//#include <CarbonCore/CarbonCore.h>

#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>


#include <IOKit/IOKitLib.h>

#include <IOKit/hid/IOHIDLib.h>

#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/IOBSD.h>

#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>

NSString *const kBTDriverManagerDidChangeStatus = @"BTDriverManagerDidChangeStatus";

//////////////////////////////////////////////////////////////
#pragma mark tablet defines
//////////////////////////////////////////////////////////////

static NSString *const kPressureKey = @"com.tantawowa.bostoDriver.pressureKey";
static NSString *const kOffsetKey = @"com.tantawowa.bostoDriver.offsetKey";
static NSString *const kSmoothingKey = @"com.tantawowa.bostoDriver.smoothingKey";
uint8_t switchToTablet[] = {0x02, 0x10, 0x01};

//////////////////////////////////////////////////////////////
#pragma mark button handling 
//////////////////////////////////////////////////////////////

int button_mapping[] = {kSystemButton1, kSystemButton1, kSystemButton2, kSystemEraser};

#define SetButtons(x)        {_stylus.button_click=((x)!=0); \
_stylus.button_mask=x; \
int qq; \
for(qq=kButtonMax;qq--;_stylus.button[qq]=((x)&(1<<qq))!=0);}

#define ResetButtons SetButtons(0)


//////////////////////////////////////////////////////////////
#pragma mark private tablet settings 
//////////////////////////////////////////////////////////////

typedef struct _settings
{
    int displayID;
    int tabletWidth;
    int tabletHeight;
    int tabletOffsetX;
    int tabletOffestY;
    int compensation;
    int average;
    int pressureLevels;
    int screenWidth;
    int screenHeight;
    int screenOffsetX;
    int screenOffsetY;
    int vendorID;
    int productID;
    int activeProfile;
    bool tabletKeys;
    int noOfTabletKeys;
    bool mouseMode;
} tabletSettings;

//Settings for Bostom 19mb

tabletSettings bostoSettings = {-1, 54290, 30682, 0, 0, 0, 0, 0, -1, -1, -1, -1, 0xED1, 0x782C, 0, false, 8, false};


dispatch_queue_t _driverDispatchQueue;

@interface BTDriverManager ()
{
    uint8_t reportBuffer[32];
}
@property(nonatomic, assign) IOHIDManagerRef hidManager;
@property(nonatomic, assign) mach_port_t io_master_port;        //!< The master port for HID events
@property(nonatomic, assign) io_connect_t gEventDriver;        //!< The connection by which HID events are sent
@property(nonatomic, assign) StylusState stylus;
@property(nonatomic, assign) StylusState oldStylus;
// global state to handle processing of state change from event to event

@property(nonatomic, assign) IOHIDDeviceRef currentDeviceRef;

@property(nonatomic) struct __IOHIDTransaction *transactionRef;


@property(nonatomic) CGRect tabletMapping;

@property(nonatomic, strong) BTScreenManager *screenManager;

@property(nonatomic) int testStartBit;

@property(nonatomic) int numberOfTestBits;

@property(nonatomic) CFRunLoopRef mainRunLoop;

@property(nonatomic) CFRunLoopRef backgroundRunLoop;

@property(nonatomic) BOOL isBackgroundLoopActive;

//calback methods
- (void)didRemoveDevice:(IOHIDDeviceRef)deviceRef withContext:(void *)context result:(IOReturn)result sender:(void *)sender;

- (void)didConnectDevice:(IOHIDDeviceRef)deviceRef withContext:(void *)context result:(IOReturn)result sender:(void *)sender;

- (void)didReceiveReport:(uint8_t *)report withID:(uint32_t)reportID;

@end



//////////////////////////////////////////////////////////////
#pragma mark c callbacks, which marshal through to our objective c methods 
//////////////////////////////////////////////////////////////

void theDeviceRemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    [[BTDriverManager shared] didRemoveDevice:device
                                  withContext:context
                                       result:result
                                       sender:sender];
}

void theDeviceMatchingCallback(void *inContext, IOReturn inResult, void *inSender, IOHIDDeviceRef inIOHIDDeviceRef) {
    [[BTDriverManager shared] didConnectDevice:inIOHIDDeviceRef
                                   withContext:inContext
                                        result:inResult
                                        sender:inSender];
}

void theInputReportCallback(void *context, IOReturn inResult, void *inSender, IOHIDReportType inReportType,
        uint32_t reportID, uint8_t *inReport, CFIndex length) {
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
    dispatch_async(_driverDispatchQueue, ^(void) {
        [[BTDriverManager shared] didReceiveReport:(uint8_t *) inReport withID:reportID];
    });
}

#define ringLength 32
int ringDepth;

// x,y coordinates and pressure level
int X[ringLength] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
int Y[ringLength] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
int P[ringLength] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};


int headX = 0;
int tailX;
long accuX = 0;

int headY = 0;
int tailY;
long accuY = 0;

int headP = 0;
int tailP;
long accuP = 0;

//////////////////////////////////////////////////////////////
#pragma mark impl 
//////////////////////////////////////////////////////////////

@implementation BTDriverManager
{

    BOOL _isConnected;
    float _pressureMod;
    bool _isDragging;
    SInt16 _eventNumber;
}

//////////////////////////////////////////////////////////////
#pragma mark - singleton impl
//////////////////////////////////////////////////////////////

+ (BTDriverManager *)shared
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
        self.mainRunLoop = CFRunLoopGetCurrent();
        self.isBackgroundLoopActive = YES;
        [self performSelectorInBackground:@selector(runDriverInBackground) withObject:nil];
//    self.testStartBit = 8;
//    self.numberOfTestBits = 16;
        NSNumber *pressureNumber = [[NSUserDefaults standardUserDefaults] objectForKey:kPressureKey];
        self.pressureDamping = [pressureNumber isKindOfClass:[NSNumber class]] ? [pressureNumber floatValue] : 0.5;

        NSNumber *smoothingNumber = [[NSUserDefaults standardUserDefaults] objectForKey:kSmoothingKey];
        self.smoothingLevel = [smoothingNumber isKindOfClass:[NSNumber class]]? [smoothingNumber intValue] : 4;

        NSArray *offsetArray = [[NSUserDefaults standardUserDefaults] objectForKey:kOffsetKey];
        self.cursorOffset = offsetArray ? NSMakePoint([offsetArray[0] floatValue], [offsetArray[1] floatValue]) : CGPointZero;

        tailX = ringDepth;
        tailY = ringDepth;
        tailP = ringDepth;

    }

    return self;
}

- (void)runDriverInBackground
{
    [self initializeHID];
    [self initializeScreenSettings];
    double resolution = 300.0;
    _driverDispatchQueue = dispatch_queue_create("com.tantawowa.bostoTabletDriver.queue", DISPATCH_QUEUE_SERIAL);
    while (self.isBackgroundLoopActive)
    {
        NSDate *theNextDate = [NSDate dateWithTimeIntervalSinceNow:resolution];
        BOOL isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:theNextDate];
    }
}

- (void)initializeScreenSettings
{
    LogInfo(@"initializing screen seettings");
    self.tabletMapping = CGRectMake(bostoSettings.tabletOffsetX, bostoSettings.tabletOffestY, bostoSettings.tabletWidth, bostoSettings.tabletHeight);
    self.screenManager = [BTScreenManager shared];
    //TODO not sure about the screenmapping anymore.
    self.screenManager.screenMapping = CGRectMake(bostoSettings.screenOffsetX, bostoSettings.screenOffsetY, bostoSettings.screenWidth, bostoSettings.screenHeight);
}

//////////////////////////////////////////////////////////////
#pragma mark HID methods
//////////////////////////////////////////////////////////////

- (void)initializeHID
{
    self.backgroundRunLoop = CFRunLoopGetCurrent();

    LogInfo(@"initializing HID device");
    self.hidManager = IOHIDManagerCreate(kIOHIDOptionsTypeNone, 0);

    CFNumberRef vendorID = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bostoSettings.vendorID);
    CFNumberRef productID = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bostoSettings.productID);

    // Create Matching dictionary
    CFMutableDictionaryRef matchingDictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    // set entries
    CFDictionarySetValue(matchingDictionary, CFSTR(kIOHIDVendorIDKey), vendorID);
    CFDictionarySetValue(matchingDictionary, CFSTR(kIOHIDProductKey), productID);


    CFRelease(productID);
    CFRelease(vendorID);

    IOHIDManagerSetDeviceMatching(self.hidManager, matchingDictionary);

    IOReturn ioReturn = IOHIDManagerOpen(self.hidManager, kIOHIDOptionsTypeSeizeDevice);

    if (ioReturn == kIOReturnSuccess)
    {
        LogInfo(@"Connectred to manager. Registering callbacks");

        IOHIDManagerRegisterDeviceRemovalCallback(self.hidManager, theDeviceRemovalCallback, NULL);
        IOHIDManagerRegisterDeviceMatchingCallback(self.hidManager, theDeviceMatchingCallback, NULL);


        IOHIDManagerScheduleWithRunLoop(self.hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

        LogInfo(@"opening HID service");
        ioReturn = [self openHIDService];
        if (ioReturn == kIOReturnSuccess)
        {
            [self initializeStylus];
        } else
        {
            LogWarn(@"error opening HID service");
        }

    } else
    {
        LogWarn(@"could not open the hid manager");
        //TODO error messaging
    }

}

- (kern_return_t)openHIDService
{
    kern_return_t kr;
    mach_port_t ev, service;

    if (KERN_SUCCESS == (kr = [self closeHIDService]))
    {
        mach_port_t port = self.io_master_port;
        if (KERN_SUCCESS == (kr = IOMasterPort(MACH_PORT_NULL, &port)) && port != MACH_PORT_NULL)
        {
            self.io_master_port = port;
            if ((service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass))))
            {
                kr = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &ev);
                IOObjectRelease(service);

                if (KERN_SUCCESS == kr)
                {
                    self.gEventDriver = ev;
                    LogInfo(@"created global event driver");
                } else
                {
                    LogWarn(@"error opening service");
                }
            } else
            {
                LogWarn(@"error opning port");
            }
        } else
        {
            LogWarn (@"error closing port before opening");
        }
    }

    return kr;
}

- (kern_return_t)closeHIDService
{
    kern_return_t r = KERN_SUCCESS;

    if (self.gEventDriver != MACH_PORT_NULL)
        r = IOServiceClose(self.gEventDriver);

    self.gEventDriver = MACH_PORT_NULL;
    return r;
}




//////////////////////////////////////////////////////////////
#pragma mark Pen methods 
//////////////////////////////////////////////////////////////



- (void)initializeStylus
{

    _stylus.toolid = kToolPen1;
    _stylus.tool = kToolTypePencil;
    _stylus.serialno = 0;

    _stylus.off_tablet = YES;
    _stylus.pen_near = NO;
    _stylus.eraser_flag = YES;

    _stylus.button_click = NO;

    ResetButtons;

    _stylus.menu_button = 0;
    _stylus.raw_pressure = 0;
    _stylus.pressure = 0;
    _stylus.tilt.x = 0;
    _stylus.tilt.y = 0;
    _stylus.point.x = 0;
    _stylus.point.y = 0;

    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(ourEvent);

    _stylus.scrPos = point;
    _stylus.oldPos.x = SHRT_MIN;
    _stylus.oldPos.y = SHRT_MIN;

    // The proximity record includes these identifiers

    // instead of making up verndor and device ids we use
    // the ids of our detected tablet
    _stylus.proximity.vendorID = (UInt16) bostoSettings.vendorID;
    _stylus.proximity.tabletID = (UInt16) bostoSettings.productID;

    _stylus.proximity.deviceID = 0x81;                // just a single device for now
    _stylus.proximity.pointerID = 0;
    _stylus.proximity.pointerType = EPen;

    _stylus.proximity.systemTabletID = 0x00;

//    _stylus.proximity.vendorPointerType = 0x0802; //0x0812;    // basic _stylus

    _stylus.proximity.pointerSerialNumber = 0x00000001;
    _stylus.proximity.reserved1 = 0;

    // This will be replaced when a tablet is located
    _stylus.proximity.uniqueID = 0x0023;

    // Indicate which fields in the point event contain valid data. This allows
    // applications to handle devices with varying capabilities.

    //
    // Use Wacom-supplied names
    //

    _stylus.proximity.pointerType = NX_TABLET_POINTER_PEN;
    _stylus.proximity.capabilityMask = kTransducerDeviceIdBitMask | kTransducerAbsXBitMask | kTransducerAbsYBitMask | kTransducerPressureBitMask;
    _stylus.proximity.vendorPointerType = 0x0802; //0x0812;    // basic _stylus


    bcopy(&_stylus, &_oldStylus, sizeof(StylusState));
}



//////////////////////////////////////////////////////////////
#pragma mark private impl
//////////////////////////////////////////////////////////////

- (void)postUpdateNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kBTDriverManagerDidChangeStatus object:self];
}


- (IOReturn)issueCommand:(IOHIDDeviceRef)deviceRef command:(uint8_t *)command
{
    return IOHIDDeviceSetReport(deviceRef,
            kIOHIDReportTypeFeature,
            2,
            command,
            3);
}

//////////////////////////////////////////////////////////////
#pragma mark HID callbacks
//////////////////////////////////////////////////////////////

- (void)didRemoveDevice:(IOHIDDeviceRef)deviceRef withContext:(void *)context result:(IOReturn)result sender:(void *)sender
{
    IOHIDDeviceUnscheduleFromRunLoop(deviceRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    self.currentDeviceRef = NULL;
    LogInfo(@"tablet removed - cleaned up references");
    _isConnected = NO;
    [self postUpdateNotification];
}

- (void)didConnectDevice:(IOHIDDeviceRef)deviceRef withContext:(void *)context result:(IOReturn)result sender:(void *)sender
{

    self.currentDeviceRef = deviceRef;

// initialize the tablet to get it going

// turn on digitizer mode
    IOReturn ioReturn = [self issueCommand:self.currentDeviceRef command:switchToTablet];
    //TODO check return value

//
    LogInfo(@"tablet connected");
    IOHIDDeviceScheduleWithRunLoop(self.currentDeviceRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(self.currentDeviceRef, reportBuffer, 4096, theInputReportCallback, "hund katze maus");
    _isConnected = YES;
    [self postUpdateNotification];
}


int getBit(char data, int i) {
    return (data >> i) & 0x01;
}

int fromBinary(char *s) {
    return (int) strtol(s, NULL, 2);
}

- (NSString *)reverseString:(NSString *)string
{
    NSMutableString *reversedString;
    int length = [string length];
    reversedString = [NSMutableString stringWithCapacity:length];

    while (length--)
    {
        [reversedString appendFormat:@"%C", [string characterAtIndex:length]];
    }

    return reversedString;
}

- (NSString *)bitStringWithInt:(int)num
{
    NSMutableString *bits = [@"" mutableCopy];
    for (int j = 0; j < 8; j++)
    {
        [bits appendFormat:@"%d", getBit(num, j)];
    }
    return bits;
}

- (NSString *)bitStringWithArray:(int [])array length:(int)length
{
    NSMutableString *bits = [@"" mutableCopy];
    for (int j = 0; j < length; j++)
    {
        [bits appendFormat:@"%d", array[j]];
    }
    return bits;
}


- (NSString *)bitStringWithBits:(int [])bits startIndex:(int)startIndex length:(int)length
{
    NSMutableString *bitString = [@"" mutableCopy];
    int end = startIndex + length;
    for (int j = startIndex; j < end; j++)
    {
        [bitString appendFormat:@"%d", bits[j]];
    }
    return [self reverseString:bitString];
}


/**
* for some reason the bosto report reports retarded data, so I had to do a lot of messing about
* to get sensible values out of it.
*/
- (void)didReceiveReport:(uint8_t *)report withID:(uint32_t)reportID
{
    //TODO optimize this.

    UInt16 bm = 0; // button mask

    int tipPressure;
    ResetButtons;  // forget the system buttons and reconstruct them in this routine

    [self calculateXYCoordsWithReport:report];
    tipPressure = report[6] | report[7] << 8;

    // tablet events are scaled to 0xFFFF (16 bit), so
    // a little shift to the right is needed
    //we also dampen the shift based on pressure

    tipPressure = MIN(tipPressure * _pressureMod, 1023);
    //TODO look at dampening

    _stylus.pressure = tipPressure << 6;

    // reconstruct the button state
    int tip = getBit(report[1], 0);
    int secondButton = getBit(report[1], 1);
    if (tip && !secondButton)
    {
        bm |= kBitStylusTip;
    }

    if (secondButton)
    {
        bm |= kBitStylusButton2;
    }


    _stylus.off_tablet = !getBit(report[1], 4);


//    LogDebug(@"update %d/%d, pres : %d(%d) off_tab %d bm %d", _stylus.point.x, _stylus.point.y, tipPressure,  _stylus.pressure, _stylus.off_tablet,bm);
    LogVerbose(@"pres : %d(%d) mod %f", tipPressure, _stylus.pressure, _pressureMod);

    // set the button state in the current stylus state
    SetButtons(bm);
//    LogDebug(@"buttonMap : %d", bm);
    [self updateStylusStatus];

    // Finally, remember the current state for next time
    bcopy(&_stylus, &_oldStylus, sizeof(self.stylus));

}

- (void)calculateXYCoordsWithReport:(uint8_t *)report
{
    //through trial and error I found that x starts at bit 15, and y at bit 31 - they are both 16 bits.
    int xCoord;
    int yCoord;
    int allBits[32];
    int index = 0;
    int j = 7;
    for (int i = 1; i < 6; i++)
    {
        while (j < 8 && index < 32)
        {
            allBits[index] = getBit(report[i], j);
            index++;
            j++;
        }
        j = 0;
    }
    xCoord = [self intWithBits:allBits startIndex:15 length:16];
    yCoord = [self intWithBits:allBits startIndex:31 length:16];

//    LogInfo(@"xbits %d, ybits %d", xCoord, yCoord);

    // LogDebug(@"update %d/%d, pres : %d off_tab xbits %@, ybits %@", xCoord, yCoord, tipPressure, xString, yString);

    // Remember the old position for tracking relative motion
    _stylus.old.x = _stylus.point.x;
    _stylus.old.y = _stylus.point.y;

    //here we smooth the values out (to avoid jitter)
    X[headX] = xCoord;

    accuX += X[headX++] - X[tailX++];
    headX %= (ringDepth << 1);
    tailX %= (ringDepth << 1);

    Y[headY] = yCoord;

    accuY += Y[headY++] - Y[tailY++];
    headY %= (ringDepth << 1);
    tailY %= (ringDepth << 1);


    // store new postion
    _stylus.point.x = accuX >> _smoothingLevel;
    _stylus.point.y = accuY >> _smoothingLevel;

    _stylus.motion.x = _stylus.point.x - _stylus.old.x;
    _stylus.motion.y = _stylus.point.y - _stylus.old.y;


    CGRect mappedCoords = [self.screenManager mapTabletCoordinatesToDisplaySpaceWithPoint:CGPointMake(xCoord, yCoord)
                                                                          toTabletMapping:self.tabletMapping];
    if (!CGPointEqualToPoint(_cursorOffset, CGPointZero))
    {
        _stylus.scrPos.x = mappedCoords.origin.x + _cursorOffset.x;
        _stylus.scrPos.y = mappedCoords.origin.y + _cursorOffset.y;
    } else
    {
        _stylus.scrPos.x = mappedCoords.origin.x;
        _stylus.scrPos.y = mappedCoords.origin.y;
    }


    //

    _stylus.ioPos.x = _stylus.scrPos.x;
    _stylus.ioPos.y = _stylus.scrPos.y;

    _stylus.subx = mappedCoords.size.width;
    _stylus.suby = mappedCoords.size.height;
}

//this method counts in reverse
- (int)intWithBits:(int [])bits startIndex:(int)startIndex length:(int)length
{
    int returnInt = 0;

    int end = startIndex - length;
    int bitIndex = length - 1;
    for (int j = startIndex; j > end; j--)
    {
        int value = bits[j] << bitIndex;
        returnInt |= value;
//        LogInfo(@"bit %d bitValue %d bitIndex %d, balue %d returnInt %d", j, bits[j], bitIndex, value, returnInt);
        bitIndex--;
    }

    return returnInt;
}

- (void)updateStylusStatus
{
    BOOL isTipDown = (_stylus.button_mask & kBitStylusTip) == kBitStylusTip;
    BOOL wasTipDown = (_oldStylus.button_mask & kBitStylusTip) == kBitStylusTip;

    BOOL isRightButtonDown = (_stylus.button_mask & kBitStylusButton2) == kBitStylusButton2;
    BOOL wasRightButtonDown = (_oldStylus.button_mask & kBitStylusButton2) == kBitStylusButton2;

//    LogDebug(@"[[[[mapped pos %d,%d to %f,%f", _stylus.point.x, _stylus.point.y, mappedPoint.x, mappedPoint.y);

    // Has the stylus moved in or out of range?
    if (_oldStylus.off_tablet != _stylus.off_tablet)
    {
        //TODO experiment to see if proximity is correctly reported
//        [self postNXEventwithType:buttonEvent
        [self postProximityEvent];
        LogVerbose(@"Stylus has %s proximity", _stylus.off_tablet ? "exited" : "entered");
        _oldStylus.off_tablet = _stylus.off_tablet;
        _isDragging = NO;
        return;
    }

    //report a click
    if (!isTipDown && wasTipDown)
    {
        LogDebug(@">>>mouseUp -drag ended");
        [self postButtonEvent:NX_LMOUSEUP withButtonNumber:0];
        _isDragging = NO;
        return;
    } else if (isTipDown && !wasTipDown && !isRightButtonDown)
    {
        LogVerbose(@">>>mouseDown");
        [self postButtonEvent:NX_LMOUSEDOWN withButtonNumber:0];
        _stylus.motion.x = 0;
        _stylus.motion.y = 0;
        _isDragging = NO;
        return;
    }


    BOOL isPenMoved = _stylus.motion.x != 0 || _stylus.motion.y != 0;
    BOOL isPressureChanged = _stylus.pressure != _oldStylus.pressure;
    if (!_isDragging && isTipDown)
    {
        if (isPenMoved || isPressureChanged)
        {
            LogVerbose(@">>>drag started");
            _isDragging = YES;
        }
    }

    //report right mouse button
    if (isRightButtonDown != wasRightButtonDown)
    {
        LogVerbose(@"[Rightmouse evet] %@", isRightButtonDown ? @"down" : @"up");
        [self postButtonEvent:isRightButtonDown ? NX_RMOUSEDOWN : NX_RMOUSEUP withButtonNumber:0];
        return;
    }

    //pointing event
    if (!_isDragging && isPenMoved)
    {
        LogVerbose(@"[Point event]");
        [self postMoveOrDragEvent:NX_MOUSEMOVED];
        return;
    }

    //dragging event
    if (_isDragging && (isPenMoved || isPressureChanged))
    {
        LogVerbose(@"[Drag event]");
        [self postMoveOrDragEvent:NX_LMOUSEDRAGGED];
        return;
    }

}

//////////////////////////////////////////////////////////////
#pragma mark posting events
//////////////////////////////////////////////////////////////


//TODO - rework this..

- (void)postProximityEvent
{
    NXEventData nxEvent;
    IOGPoint newPoint = {_stylus.scrPos.x, _stylus.scrPos.y};

    bzero(&nxEvent, sizeof(NXEventData));
    nxEvent.mouseMove.subx = _stylus.subx;
    nxEvent.mouseMove.suby = _stylus.suby;
    nxEvent.mouseMove.subType = NX_SUBTYPE_TABLET_PROXIMITY;
    bcopy(&_stylus.proximity, &nxEvent.mouseMove.tablet.proximity, sizeof(NXTabletProximityData));
    nxEvent.mouseMove.tablet.proximity.enterProximity = _stylus.off_tablet ? 0 : 1;
    IOHIDPostEvent(self.gEventDriver, NX_MOUSEMOVED, newPoint, &nxEvent, kNXEventDataVersion, 0, 0);

    bzero(&nxEvent, sizeof(NXEventData));
    bcopy(&_stylus.proximity, &nxEvent.proximity, sizeof(NXTabletProximityData));
    nxEvent.proximity.enterProximity = _stylus.off_tablet ? 0 : 1;
    IOHIDPostEvent(self.gEventDriver, NX_TABLETPROXIMITY, newPoint, &nxEvent, kNXEventDataVersion, 0, 0);
}


- (void)postMoveOrDragEvent:(UInt32)eventType
{
    NXEventData nxEvent;
    IOGPoint newPoint = {_stylus.scrPos.x, _stylus.scrPos.y};

    bzero(&nxEvent, sizeof(NXEventData));
    nxEvent.mouseMove.dx = (SInt32) (_stylus.ioPos.x - _oldStylus.ioPos.x);
    nxEvent.mouseMove.dy = (SInt32) (_stylus.ioPos.y - _oldStylus.ioPos.y);
    nxEvent.mouseMove.subType = NX_SUBTYPE_TABLET_POINT;
    nxEvent.mouseMove.subx = _stylus.subx;
    nxEvent.mouseMove.suby = _stylus.suby;
    nxEvent.mouseMove.tablet.point.x = _stylus.report.x;
    nxEvent.mouseMove.tablet.point.y = _stylus.report.y;
    nxEvent.mouseMove.tablet.point.buttons = _stylus.report.buttons;
    nxEvent.mouseMove.tablet.point.pressure = _stylus.pressure;
    nxEvent.mouseMove.tablet.point.deviceID = _stylus.proximity.deviceID;
    IOHIDPostEvent(self.gEventDriver, eventType, newPoint, &nxEvent, kNXEventDataVersion, 0, kIOHIDSetCursorPosition);

}

- (void)postButtonEvent:(UInt32)eventType withButtonNumber:(UInt8)btnNumber
{
    NXEventData nxEvent;
    IOGPoint newPoint = {_stylus.scrPos.x, _stylus.scrPos.y};

    bzero(&nxEvent, sizeof(NXEventData));
    nxEvent.mouse.click = 0;
    nxEvent.mouse.subx = _stylus.subx;
    nxEvent.mouse.suby = _stylus.suby;
    nxEvent.mouse.eventNum = _eventNumber++;
    nxEvent.mouse.pressure = _stylus.pressure;
    nxEvent.mouse.buttonNumber = btnNumber;
    nxEvent.mouse.subType = NX_SUBTYPE_TABLET_POINT;
    nxEvent.mouse.tablet.point.x = _stylus.report.x;
    nxEvent.mouse.tablet.point.y = _stylus.report.y;
    nxEvent.mouse.tablet.point.buttons = _stylus.report.buttons;
    nxEvent.mouse.tablet.point.pressure = _stylus.report.pressure;
    nxEvent.mouse.tablet.point.deviceID = _stylus.proximity.deviceID;
    IOHIDPostEvent(self.gEventDriver, eventType, newPoint, &nxEvent, kNXEventDataVersion, 0, 0);
}


//////////////////////////////////////////////////////////////
#pragma mark screen mapping methods 
//////////////////////////////////////////////////////////////

//
// InitTabletBounds
//
// Initialize the active tablet region.
// This is called to set the initial mapping of the tablet.
// Command-line arguments might leave some of these set to -1.
// The rest are set when the tablet dimensions are received.
//
- (void)setTabletMapping:(CGRect)tabletMapping
{
    float x = (tabletMapping.origin.x != -1) ? tabletMapping.origin.x : 0;
    float y = (tabletMapping.origin.y != -1) ? tabletMapping.origin.y : 0;
    float w = (tabletMapping.size.width != -1) ? (tabletMapping.size.width - tabletMapping.origin.x + 1) : bostoSettings.tabletWidth;
    float h = (tabletMapping.size.height != -1) ? (tabletMapping.size.height - tabletMapping.origin.y + 1) : bostoSettings.tabletHeight;
    _tabletMapping = CGRectMake(x, y, w, h);
}


//////////////////////////////////////////////////////////////
#pragma mark public api 
//////////////////////////////////////////////////////////////

- (BOOL)isConnected
{
    return _isConnected;
}

- (void)setSmoothingLevel:(int)smoothingLevel
{
    _smoothingLevel = smoothingLevel;
    ringDepth = 1 << smoothingLevel;
    headX = 0;
    headY = 0;
    tailX = 0;
    tailY = 0;
    accuX = 0;
    accuY = 0;
    tailX = ringDepth;
    tailY = ringDepth;
    for (int i = 0; i < ringLength; i++)
    {
        X[i] = 0;
        Y[i] = 0;
    }

    [[NSUserDefaults standardUserDefaults] setObject:@(smoothingLevel) forKey:kSmoothingKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    LogInfo(@"smoothing level set to %d", smoothingLevel);
    [self postUpdateNotification];
}


- (void)setPressureDamping:(float)pressureDamping
{
    _pressureDamping = pressureDamping;
    [[NSUserDefaults standardUserDefaults] setObject:@(pressureDamping) forKey:kPressureKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    _pressureMod = 0.5 - self.pressureDamping;
    _pressureMod = 1 - _pressureMod;
    LogInfo(@"pressure damping %f mod is %f", pressureDamping, _pressureMod);
    [self postUpdateNotification];
}


- (void)reinitialize
{
    LogInfo(@"Reinitializing driver");
    if (self.currentDeviceRef)
    {
        LogInfo(@"Device was connected, emulating device remove");
        [self didRemoveDevice:self.currentDeviceRef
                  withContext:nil result:nil sender:nil];
    }
    [self closeHIDService];
    [self initializeHID];

}

- (void)setCursorOffset:(CGPoint)cursorOffset
{
    _cursorOffset = cursorOffset;
    NSValue *offsetObject = [NSValue valueWithPoint:cursorOffset];
    [[NSUserDefaults standardUserDefaults] setObject:@[@(cursorOffset.x), @(cursorOffset.y)] forKey:kOffsetKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    LogInfo(@"offset set to %@", NSStringFromPoint(cursorOffset));
    [self postUpdateNotification];
}

- (void)sendMouseUpEventToUnblockTheMouse
{
    [self postButtonEvent:NX_LMOUSEUP withButtonNumber:0];
}
@end