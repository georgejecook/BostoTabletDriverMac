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

//////////////////////////////////////////////////////////////
#pragma mark impl 
//////////////////////////////////////////////////////////////

@implementation BTDriverManager
{

    BOOL _isConnected;
    float _pressureMod;
    bool _isDragging;
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
    }
//    self.testStartBit = 8;
//    self.numberOfTestBits = 16;
    NSNumber *pressureNumber = [[NSUserDefaults standardUserDefaults] objectForKey:kPressureKey];
    self.pressureDamping = pressureNumber ? [pressureNumber floatValue] : 0.5;

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
//	_stylus.proximity.vendorID =  0x056A; // 0xBEEF;				// A made-up Vendor ID (Wacom's is 0x056A)
//	_stylus.proximity.tabletID = 0x0001;
//
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
    _stylus.proximity.uniqueID = 0;

    // Indicate which fields in the point event contain valid data. This allows
    // applications to handle devices with varying capabilities.

//    _stylus.proximity.capabilityMask =
//            NX_TABLET_CAPABILITY_DEVICEIDMASK
//                    | NX_TABLET_CAPABILITY_ABSXMASK | NX_TABLET_CAPABILITY_ABSYMASK | NX_TABLET_CAPABILITY_BUTTONSMASK
//                    //| NX_TABLET_CAPABILITY_TILTXMASK | NX_TABLET_CAPABILITY_TILTYMASK
//                    | NX_TABLET_CAPABILITY_PRESSUREMASK
//                    | NX_TABLET_CAPABILITY_TANGENTIALPRESSUREMASK
//                    | kTransducerPressureBitMask;
//

    //
    // Use Wacom-supplied names
    //

    _stylus.proximity.pointerType = NX_TABLET_POINTER_PEN;
//    eventData.proximity.capabilityMask = NX_TABLET_CAPABILITY_PRESSUREMASK;
//    eventData.proximity.capabilityMask = _stylus.proximity.capabilityMask;
    _stylus.proximity.capabilityMask = kTransducerDeviceIdBitMask | kTransducerAbsXBitMask | kTransducerAbsYBitMask | kTransducerPressureBitMask;
    _stylus.proximity.vendorPointerType = 0x0802; //0x0812;    // basic _stylus


    bcopy(&_stylus, &_oldStylus, sizeof(StylusState));
}



//////////////////////////////////////////////////////////////
#pragma mark private impl
//////////////////////////////////////////////////////////////

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
    [[NSNotificationCenter defaultCenter] postNotificationName:kBTDriverManagerDidChangeStatus object:self];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kBTDriverManagerDidChangeStatus object:self];
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

    [self calculateXYCoordsWithBits:report];
    tipPressure = report[6] | report[7] << 8;

    // tablet events are scaled to 0xFFFF (16 bit), so
    // a little shift to the right is needed
    //we also dampen the shift based on pressure

    tipPressure = MIN(tipPressure * _pressureMod, 1023);
    //TODO look at dampening
//    if (tipPressure < 512)
//    {
//        _stylus.pressure = tipPressure << 6;
//    } else
//    {
//        _stylus.pressure = tipPressure << 7;
//    }
//        _stylus.pressure = tipPressure << 7;

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

- (void)calculateXYCoordsWithBits:(uint8_t *)report
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

    // store new postion
    _stylus.point.x = xCoord;
    _stylus.point.y = yCoord;

    _stylus.motion.x = _stylus.point.x - _stylus.old.x;
    _stylus.motion.y = _stylus.point.y - _stylus.old.y;
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

    CGPoint mappedPoint = [self.screenManager mapTabletCoordinatesToDisplaySpaceWithPoint:CGPointMake(_stylus.point.x, _stylus.point.y)
                                                                          toTabletMapping:self.tabletMapping];
    _stylus.scrPos.x = mappedPoint.x;
    _stylus.scrPos.y = mappedPoint.y;
//    LogDebug(@"[[[[mapped pos %d,%d to %f,%f", _stylus.point.x, _stylus.point.y, mappedPoint.x, mappedPoint.y);

    // Has the stylus moved in or out of range?
    if (_oldStylus.off_tablet != _stylus.off_tablet)
    {
        //TODO experiment to see if proximity is correctly reported
//        [self postNXEventwithType:buttonEvent
        [self postNXEventwithType:NX_MOUSEMOVED subType:NX_SUBTYPE_TABLET_PROXIMITY buttonNumber:0];
        LogVerbose(@"Stylus has %s proximity", _stylus.off_tablet ? "exited" : "entered");
        _oldStylus.off_tablet = _stylus.off_tablet;
        _isDragging = NO;
        return;
    }

    // TODO - double click processing Is a Double-Click warranted?
//    if (buttonState[kSystemDoubleClick] && !oldButtonState[kSystemDoubleClick])
//    {
//        if (oldButtonState[kSystemButton1])
//        {
//            [self postNXEventwithType:NX_LMOUSEUP subType:NX_SUBTYPE_TABLET_POINT otherButton:0];
//
//        }
//
//        PostNXEvent(NX_LMOUSEDOWN, NX_SUBTYPE_TABLET_POINT, 0);
//
//        PostNXEvent(NX_LMOUSEUP, NX_SUBTYPE_TABLET_POINT, 0);
//
//        PostNXEvent(NX_LMOUSEDOWN, NX_SUBTYPE_TABLET_POINT, 0);
//
//        if (!oldButtonState[kSystemButton1])
//        {
//
//            PostNXEvent(NX_LMOUSEUP, NX_SUBTYPE_TABLET_POINT, 0);
//        }
//
//        isEventPosted = YES;
//    }

    //report a click
//    if (_stylus.pressure == 0 && _oldStylus.pressure != 0)
    if (!isTipDown && wasTipDown)
    {
        LogDebug(@">>>mouseUp -drag ended");
        [self postNXEventwithType:NX_LMOUSEUP subType:NX_SUBTYPE_TABLET_POINT buttonNumber:0];
        _isDragging = NO;
        return;
    } else if (isTipDown && !wasTipDown && !isRightButtonDown)
    {
        LogVerbose(@">>>mouseDown");
        [self postNXEventwithType:NX_LMOUSEDOWN subType:NX_SUBTYPE_TABLET_POINT buttonNumber:0];
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
        [self postNXEventwithType:isRightButtonDown ? NX_RMOUSEDOWN : NX_RMOUSEUP
                          subType:NX_SUBTYPE_TABLET_POINT
                     buttonNumber:0];
        return;
    }

    //pointing event
    if (!_isDragging && isPenMoved)
    {
        LogVerbose(@"[Point event]");
        [self postNXEventwithType:NX_MOUSEMOVED subType:NX_SUBTYPE_TABLET_POINT buttonNumber:0];
        return;
    }

    //dragging event
    if (_isDragging && (isPenMoved || isPressureChanged))
    {
        LogVerbose(@"[Drag event]");
        [self postNXEventwithType:NX_LMOUSEDRAGGED subType:NX_SUBTYPE_TABLET_POINT buttonNumber:0];
        return;
    }

}

//////////////////////////////////////////////////////////////
#pragma mark posting events
//////////////////////////////////////////////////////////////


- (void)postNXEventwithType:(int)eventType subType:(SInt16)eventSubType buttonNumber:(UInt8)buttonNumber
{
    static NXEventData eventData;

    switch (eventType)
    {
        //TODO what are these
        case NX_OMOUSEUP:
        case NX_OMOUSEDOWN:
            LogDebug(@"[NX_OMOUSEUP/NX_OMOUSEDOWN event]");
            eventData.mouse.click = 0;
            eventData.mouse.buttonNumber = buttonNumber;
            break;


        case NX_LMOUSEDOWN:
        case NX_RMOUSEDOWN:
        case NX_RMOUSEUP:
        case NX_LMOUSEUP:
        {
            NSString *buttonString = ((eventType == NX_LMOUSEDOWN || eventType == NX_LMOUSEUP) ? @"Left" : @"right");
            NSString *buttonUPDownString = ((eventType == NX_LMOUSEDOWN || eventType == NX_RMOUSEDOWN) ? @"Down" : @"UP");
            LogDebug(@"[%@mouse%@ event button %d]", buttonString, buttonUPDownString, buttonNumber);
            eventData.mouse.pressure = 0;
            eventData.mouse.subType = eventSubType;
            eventData.mouse.subx = 0;
            eventData.mouse.suby = 0;
            eventData.mouse.buttonNumber = buttonNumber;

            switch (eventSubType)
            {
                case NX_SUBTYPE_TABLET_POINT:
                    bcopy(&_stylus.proximity, &eventData.mouse.tablet.proximity, sizeof(_stylus.proximity));

                    eventData.mouse.tablet.point.x = _stylus.point.x;
                    eventData.mouse.tablet.point.y = _stylus.point.y;
                    eventData.mouse.tablet.point.buttons = 0x0000;
                    eventData.mouse.tablet.point.tilt.x = _stylus.tilt.x;
                    eventData.mouse.tablet.point.tilt.y = _stylus.tilt.y;
                    break;

                case NX_SUBTYPE_TABLET_PROXIMITY:
                    bcopy(&_stylus.proximity, &eventData.mouse.tablet.proximity, sizeof(_stylus.proximity));
                    break;
                default:
                    break;
            }
            break;
        }
        case NX_MOUSEMOVED:
        case NX_LMOUSEDRAGGED:
        case NX_RMOUSEDRAGGED:
            LogDebug(@"[%@ event]", eventType == NX_MOUSEMOVED ? @"Move" : @"Drag");
            bcopy(&_stylus.proximity, &eventData.mouse.tablet.proximity, sizeof(_stylus.proximity));
            bcopy(&_stylus.proximity, &eventData.mouseMove.tablet.proximity, sizeof(_stylus.proximity));
            eventData.mouse.buttonNumber = 0;
            eventData.mouseMove.subType = eventSubType;
            switch (eventSubType)
            {
                case NX_SUBTYPE_TABLET_POINT:
                    eventData.mouseMove.tablet.point.x = _stylus.point.x;
                    eventData.mouseMove.tablet.point.y = _stylus.point.y;
                    eventData.mouseMove.tablet.point.buttons = 0x0000;
                    eventData.mouseMove.tablet.point.tilt.x = _stylus.tilt.x;
                    eventData.mouseMove.tablet.point.tilt.y = _stylus.tilt.y;
                    break;

                case NX_SUBTYPE_TABLET_PROXIMITY:
                    bcopy(&_stylus.proximity, &eventData.mouseMove.tablet.proximity, sizeof(NXTabletProximityData));
                    break;
                default:
                    break;
            }

            // Relative motion is needed for the mouseMove event
            if (_stylus.oldPos.x == SHRT_MIN)
            {
                eventData.mouseMove.dx = eventData.mouseMove.dy = 0;
            }
            else
            {
                eventData.mouseMove.dx = (SInt32) (_stylus.scrPos.x - _stylus.oldPos.x);
                eventData.mouseMove.dy = (SInt32) (_stylus.scrPos.y - _stylus.oldPos.y);
            }
            eventData.mouseMove.subx = 0;
            eventData.mouseMove.suby = 0;
            _stylus.oldPos = _stylus.scrPos;
            break;
        default:
            break;
    }

    bcopy(&_stylus.proximity, &eventData.mouse.tablet.proximity, sizeof(_stylus.proximity));
    bcopy(&_stylus.proximity, &eventData.mouseMove.tablet.proximity, sizeof(_stylus.proximity));

    eventData.mouseMove.tablet.point.pressure = _stylus.pressure;

    // Generate the tablet event to the system event driver
    IOGPoint newPoint = {_stylus.scrPos.x, _stylus.scrPos.y};
    LogDebug(@"[POSTING] pos: %d,%d, eventdata.pressure %d(s.pressure) %d cap mask %d", newPoint.x, newPoint.y, eventData.mouseMove.tablet.point.pressure, _stylus.pressure, eventData.mouseMove.tablet.proximity.capabilityMask);

//    if (NO && eventType == NX_LMOUSEDOWN)
//    {
//
//        NSEvent *dragEvent = [NSEvent mouseEventWithType:eventType
//                                                location:NSMakePoint(newPoint.x, newPoint.y)
//                                           modifierFlags:0
//                                               timestamp:[[NSDate date] timeIntervalSince1970]
//                                            windowNumber:0
//                                                 context:nil eventNumber:0
//                                              clickCount:1
//                                                pressure:_stylus.pressure];
//        CGEventRef cgEvent = [dragEvent CGEvent];
//        CGEventPost(kCGHIDEventTap, cgEvent);
//
//
//    } else
//    {

    if (eventSubType == NX_SUBTYPE_TABLET_PROXIMITY)
    {
        // we always post a proximity event individually
        LogDebug(@"[POST] Proximity Event %d Subtype %d", NX_TABLETPROXIMITY, NX_SUBTYPE_TABLET_PROXIMITY);
        bcopy(&_stylus.proximity, &eventData.proximity, sizeof(NXTabletProximityData));
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
//        dispatch_sync(dispatch_get_main_queue(),^ {
        (void) IOHIDPostEvent(self.gEventDriver, NX_TABLETPROXIMITY, newPoint, &eventData, kNXEventDataVersion, 0, 0);
//        });
    } else
    {
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
//        dispatch_sync(dispatch_get_main_queue(),^ {
        (void) IOHIDPostEvent(self.gEventDriver, eventType, newPoint, &eventData, kNXEventDataVersion, 0, kIOHIDSetCursorPosition);
//        });
    }
}

//////////////////////////////////////////////////////////////
#pragma mark screen mapping methods 
//////////////////////////////////////////////////////////////

//TODO refactor into it's own class



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
#pragma mark debugging code I used to figure out the values in the report
//////////////////////////////////////////////////////////////


//debugging to help us work out the report bytes (it seems that the bytes are somewhat up the spout on their input report
//I'm leaving debug code in here (commented out)in case others have slightly different bosto monitors
//this was in init
//    [NSEvent addGlobalMonitorForEventsMatchingMask:(NSKeyUpMask) handler:^(NSEvent *event) {
//        if (event.keyCode == 126)
//        {
//            self.testStartBit++;
//            LogDebug(@"testStartBit now %d", self.testStartBit);
//        } else if (event.keyCode == 125)
//        {
//            self.testStartBit--;
//            LogDebug(@"testStartBit now %d", self.testStartBit);
//        } else if (event.keyCode == 124)
//        {
//            self.numberOfTestBits++;
//            LogDebug(@"numbits now %d", self.numberOfTestBits);
//        } else if (event.keyCode == 123)
//        {
//            self.numberOfTestBits--;
//            LogDebug(@"numberOfTestBits now %d", self.numberOfTestBits);
//        }
//    }];


/**
* code I used to work out what was actually in the report
*
- (void)didReceiveReport:(uint8_t *)report withID:(uint32_t)reportID
{

    UInt16 bm = 0; // button mask


    int xCoord;
    int yCoord;
    int tipPressure;

    ResetButtons;  // forget the system buttons and reconstruct them in this routine

    NSMutableString *bits = [@"" mutableCopy];
    NSMutableString *counter = [@"" mutableCopy];
    NSMutableString *line = [@"" mutableCopy];
    NSMutableString *byte = [@"" mutableCopy];
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            [bits appendFormat:@"%d", getBit(report[i], j)];
            [counter appendFormat:@"%d", j];
            [line appendString:@"-"];
        }
        [byte appendFormat:@"byte %d  ", i];
    }

    NSString *bitString = [bits substringWithRange:NSMakeRange(self.testStartBit, _numberOfTestBits)];
    xCoord = fromBinary([bitString UTF8String]);
    NSString *reversedBitString = [self reverseString:bitString];
    int reversedValue = fromBinary([reversedBitString UTF8String]);

    tipPressure = report[6] | report[7] << 8;
    LogDebug(@"start %d: %d (%@), altX %d (%@)", self.testStartBit, xCoord, bitString, reversedValue, reversedBitString);

*/


//////////////////////////////////////////////////////////////
#pragma mark public api 
//////////////////////////////////////////////////////////////

- (BOOL)isConnected
{
    return _isConnected;
}

- (void)setPressureDamping:(float)pressureDamping
{
    _pressureDamping = pressureDamping;
    [[NSUserDefaults standardUserDefaults] setObject:@(pressureDamping) forKey:kPressureKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    _pressureMod = 0.5 - self.pressureDamping;
    _pressureMod = 1 - _pressureMod;
    LogInfo(@"pressure damping %f mod is %f", pressureDamping, _pressureMod);

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

- (void)sendMouseUpEventToUnblockTheMouse
{
    [self postNXEventwithType:NX_LMOUSEUP subType:NX_SUBTYPE_TABLET_POINT buttonNumber:0];
}
@end