//
// Created by georgecook on 15/03/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import "BTDriverManager.h"
#import "BTMacros.h"
#import "stylus.h"
#import "BTScreenManager.h"
//#include <CarbonCore/CarbonCore.h>

#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>


#include <IOKit/IOKitLib.h>

#include <IOKit/hid/IOHIDLib.h>

#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/IOBSD.h>

#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>

//////////////////////////////////////////////////////////////
#pragma mark tablet defines
//////////////////////////////////////////////////////////////

#define        kTransducerPressureBitMask                    0x0400

uint8_t switchToTablet[] = {0x02, 0x10, 0x01};

//////////////////////////////////////////////////////////////
#pragma mark button handling 
//////////////////////////////////////////////////////////////

// button handling is done within a 16 Bit integer used as bit field
bool buttonState[kSystemClickTypes];        //!< The state of all the system-level buttons
bool oldButtonState[kSystemClickTypes];    //!< The previous state of all system-level buttons

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

tabletSettings bostoSettings = {-1, 6000, 4500, 0, 0, 0, 0, 0, -1, -1, -1, -1, 0x08ca, 0x0010, 0, false, 8, false};


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

@property(nonatomic) struct __IOHIDElement *xHIDElementRef;

@property(nonatomic) struct __IOHIDElement *yHIDElementRef;

@property(nonatomic) struct __IOHIDElement *proximityHIDElementRef;

@property(nonatomic) struct __IOHIDElement *pressureHIDElementRef;

@property(nonatomic) struct __IOHIDTransaction *transactionRef;


@property(nonatomic) CGRect const tabletMapping;

@property(nonatomic, strong) BTScreenManager *screenManager;

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
    //we don't care about anything else, because we want to move to transactions anyhow.
    [[BTDriverManager shared] didReceiveReport:(uint8_t *) inReport withID:reportID];

}

//////////////////////////////////////////////////////////////
#pragma mark c functions 
//////////////////////////////////////////////////////////////

//TODO make a macro or something
int valueForElement(IOHIDElementRef element, IOHIDDeviceRef deviceRef) {
    IOHIDValueRef valueRef;
    IOHIDDeviceGetValue(deviceRef, element, &valueRef);
    int returnValue = IOHIDValueGetIntegerValue(valueRef);
    CFRelease(valueRef);
    return returnValue;

//    if (valueRef)
//    {
//        double scaled = IOHIDValueGetScaledValue(valueRef, kIOHIDValueScaleTypePhysical);
//        return scaled;
//    }
//    return 0;
//
}


//////////////////////////////////////////////////////////////
#pragma mark impl 
//////////////////////////////////////////////////////////////



@implementation BTDriverManager
{

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
        [self initializeHID];
        [self initializeScreenSettings];
    }

    return self;
}

- (void)initializeScreenSettings
{
    NSLog(@"initializing screen seettings");
    self.tabletMapping = CGRectMake(bostoSettings.tabletOffsetX, bostoSettings.tabletOffestY, bostoSettings.tabletWidth, bostoSettings.tabletHeight);
    self.screenManager = [[BTScreenManager alloc] init];
    [self.screenManager updateDisplaysBoundsWithDisplayId:bostoSettings.displayID]; //TODO - allow users to provide an override for this
    self.screenManager.screenMapping = CGRectMake(bostoSettings.screenOffsetX, bostoSettings.screenOffsetY, bostoSettings.screenWidth, bostoSettings.screenHeight);
}

//////////////////////////////////////////////////////////////
#pragma mark HID methods
//////////////////////////////////////////////////////////////

- (void)initializeHID
{
    NSLog(@"initializing HID device");
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
        NSLog(@"Connectred to manager. Registering callbacks");

        IOHIDManagerRegisterDeviceRemovalCallback(self.hidManager, theDeviceRemovalCallback, NULL);
        IOHIDManagerRegisterDeviceMatchingCallback(self.hidManager, theDeviceMatchingCallback, NULL);

        IOHIDManagerScheduleWithRunLoop(self.hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

        NSLog(@"opening HID service");
        ioReturn = [self openHIDService];
        if (ioReturn == kIOReturnSuccess)
        {
            [self initializeStylus];
        } else
        {
            NSLog(@"error opening HID service");
        }

    } else
    {
        NSLog(@"could not open the hid manager");
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
        if (KERN_SUCCESS == (kr = IOMasterPort(MACH_PORT_NULL, &port)) && self.io_master_port != MACH_PORT_NULL)
        {
            if ((service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass))))
            {
                kr = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &ev);
                IOObjectRelease(service);

                if (KERN_SUCCESS == kr)
                    self.gEventDriver = ev;
            }
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

    _stylus.off_tablet = true;
    _stylus.pen_near = false;
    _stylus.eraser_flag = false;

    _stylus.button_click = false;

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
    _stylus.proximity.pointerID = 0x03;

    _stylus.proximity.systemTabletID = 0x00;

    _stylus.proximity.vendorPointerType = 0x0812;    // basic _stylus

    _stylus.proximity.pointerSerialNumber = 0x00000001;
    _stylus.proximity.reserved1 = 0;

    // This will be replaced when a tablet is located
    _stylus.proximity.uniqueID = 0;

    // Indicate which fields in the point event contain valid data. This allows
    // applications to handle devices with varying capabilities.

    _stylus.proximity.capabilityMask =
            NX_TABLET_CAPABILITY_DEVICEIDMASK
                    | NX_TABLET_CAPABILITY_ABSXMASK | NX_TABLET_CAPABILITY_ABSYMASK | NX_TABLET_CAPABILITY_BUTTONSMASK
                    //| NX_TABLET_CAPABILITY_TILTXMASK | NX_TABLET_CAPABILITY_TILTYMASK
                    | NX_TABLET_CAPABILITY_PRESSUREMASK
//                    | NX_TABLET_CAPABILITY_TANGENTIALPRESSUREMASK
                    | kTransducerPressureBitMask;


    //
    // Use Wacom-supplied names
    //

    bcopy(&_stylus, &_oldStylus, sizeof(StylusState));
    bzero(buttonState, sizeof(buttonState));
    bzero(oldButtonState, sizeof(oldButtonState));
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
    self.currentDeviceRef = NULL;
    IOHIDDeviceUnscheduleFromRunLoop(deviceRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    NSLog(@"tablet removed");
}

- (void)didConnectDevice:(IOHIDDeviceRef)deviceRef withContext:(void *)context result:(IOReturn)result sender:(void *)sender
{

    self.currentDeviceRef = deviceRef;

// initialize the tablet to get it going

// turn on digitizer mode
    IOReturn ioReturn = [self issueCommand:self.currentDeviceRef command:switchToTablet];
    //TODO check return value

//
    NSLog(@"tablet connected");
    IOHIDDeviceScheduleWithRunLoop(self.currentDeviceRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    CFArrayRef elemAry = IOHIDDeviceCopyMatchingElements(self.currentDeviceRef, NULL, 0);
    self.xHIDElementRef = (IOHIDElementRef) CFArrayGetValueAtIndex(elemAry, 8);
    self.yHIDElementRef = (IOHIDElementRef) CFArrayGetValueAtIndex(elemAry, 9);
    self.proximityHIDElementRef = (IOHIDElementRef) CFArrayGetValueAtIndex(elemAry, 6);
    self.pressureHIDElementRef = (IOHIDElementRef) CFArrayGetValueAtIndex(elemAry, 10); //also 11, and 12

//    xScaleFactor = hpSettings.screenWidth / 27135; //TODO get this from the element
//    yScaleFactor = hpSettings.screenWidth / 15300; //TODO get this from the element, these are observed values right now
    IOHIDDeviceRegisterInputReportCallback(self.currentDeviceRef, reportBuffer, 512, theInputReportCallback, "hund katze maus");


    //TODO - work out how to do this
//    self.transactionRef = IOHIDTransactionCreate(
//        kCFAllocatorDefault,
//        self.currentDeviceRef,
//        kIOHIDTransactionDirectionTypeInput,
//        kIOHIDOptionsTypeNone);
//    IOHIDTransactionAddElement(self.transactionRef, self.xHIDElementRef);
//    IOHIDTransactionAddElement(self.transactionRef, self.yHIDElementRef);
//    IOHIDTransactionAddElement(self.transactionRef, self.proximityHIDElementRef);
//    IOHIDTransactionAddElement(self.transactionRef, self.pressureHIDElementRef);
//    IOHIDTransactionCommit(self.transactionRef);
//    IOHIDTransactionScheduleWithRunLoop(self.transactionRef, CFRunLoopGetCurrent( ), kCFRunLoopDefaultMode );
}

- (void)didReceiveReport:(uint8_t *)report withID:(uint32_t)reportID
{
    UInt16 bm = 0; // button mask

    SInt32 currentX = (SInt32) valueForElement(_xHIDElementRef, _currentDeviceRef);
    SInt32 currentY = (SInt32) valueForElement(_yHIDElementRef, _currentDeviceRef);

    double pressure = valueForElement(_pressureHIDElementRef, _currentDeviceRef);
    pressure = ((pressure * (unsigned long long) 0xffff) / (unsigned) (1024LL)); //scale value up to internal representation
    _stylus.pressure = (UInt16) pressure;

    SInt32 deltaX = _stylus.old.x - currentX;
    SInt32 deltaY = _stylus.old.y - currentY;

    ResetButtons;

    _stylus.old.x = _stylus.point.x;
    _stylus.old.y = _stylus.point.y;

    _stylus.point.x = currentX;
    _stylus.point.y = currentY;

    _stylus.motion.x = deltaX;
    _stylus.motion.y = deltaY;
    _stylus.off_tablet = !valueForElement(_proximityHIDElementRef, _currentDeviceRef);

    NSLog(@"update %d/%d, pres : %d(%f) off_tab %d", _stylus.point.x, _stylus.point.y, _stylus.pressure, pressure, _stylus.off_tablet);

    if (_stylus.pressure > 0)
    {
        bm |= kBitStylusTip;
    }
    //    bm |= kBitStylusButton2; //TODO check for button 2

    // set the button state in the current stylus state
    SetButtons(bm);
    [self updateStylusStatus];
}

- (void)updateStylusStatus
{
    static bool dragState = false;

    // Map Stylus buttons to system buttons
    bzero(buttonState, sizeof(buttonState));
    _stylus.button[kStylusTip] = _stylus.pressure > 0;
    buttonState[button_mapping[kStylusTip]] |= _stylus.button[kStylusTip];

    // buttonState[button_mapping[kStylusButton1]] |= _stylus.button[kStylusTip];
//    buttonState[button_mapping[kStylusButton1]] |= _stylus.button[kStylusButton1];

    int buttonEvent = (dragState || buttonState[kSystemClickOrRelease] || buttonState[kSystemButton1]) ? NX_LMOUSEDRAGGED : (buttonState[kSystemButton2] ? NX_RMOUSEDRAGGED : NX_MOUSEMOVED);

    bool isEventPosted = false;

    // Has the stylus moved in or out of range?
    if (_oldStylus.off_tablet != _stylus.off_tablet)
    {
        [self postNXEventwithType:buttonEvent
                          subType:NX_SUBTYPE_TABLET_PROXIMITY otherButton:0];
        NSLog(@"Stylus has %s proximity", _stylus.off_tablet ? "exited" : "entered");
        _oldStylus.off_tablet = _stylus.off_tablet;
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
//        isEventPosted = true;
//    }

    //report a click
    if (_stylus.pressure == 0 && _oldStylus.pressure != 0)
    {
        [self postNXEventwithType:NX_LMOUSEUP subType:NX_SUBTYPE_TABLET_POINT otherButton:0];
        isEventPosted = true;
    } else if (_stylus.pressure != 0 && _oldStylus.pressure == 0)
    {
        [self postNXEventwithType:NX_LMOUSEDOWN subType:NX_SUBTYPE_TABLET_POINT otherButton:0];
        isEventPosted = true;
    }

    //Drag
    if (!buttonState[kSystemClickOrRelease] && oldButtonState[kSystemClickOrRelease])
    {
        dragState = !dragState;

        if (!dragState || !buttonState[kSystemButton1])
        {
            [self postNXEventwithType:(dragState ? NX_LMOUSEDOWN : NX_LMOUSEUP)
                              subType:NX_SUBTYPE_TABLET_POINT otherButton:0];

            isEventPosted = true;
            NSLog(@"Drag %sed", dragState ? "Start" : "End");
        }
    }

    // Has Button 1 changed?
    if (oldButtonState[kSystemButton1] != buttonState[kSystemButton1])
    {
        if (dragState && !buttonState[kSystemButton1])
        {
            dragState = false;
            NSLog(@"Drag Canceled");
        }

        if (!dragState)
        {
            [self postNXEventwithType:(buttonState[kSystemButton1] ? NX_LMOUSEDOWN : NX_LMOUSEUP)
                              subType:NX_SUBTYPE_TABLET_POINT otherButton:0];

            isEventPosted = true;
        }
    }

    // Has Button 2 changed?
    if (oldButtonState[kSystemButton2] != buttonState[kSystemButton2])
    {
//        [self postNXEventwithType:(buttonState[kSystemButton2] ? NX_LMOUSEDOWN : NX_LMOUSEUP)
//                                      subType:NX_SUBTYPE_TABLET_POINT otherButton:0];
//        isEventPosted = true;
    }

    // Has the stylus changed position?
    if (!isEventPosted && (_oldStylus.point.x != _stylus.point.x || _oldStylus.point.y != _stylus.point.y))
    {
        NSLog(@"position changed");
        [self postNXEventwithType:buttonEvent
                          subType:NX_SUBTYPE_TABLET_POINT otherButton:0];

    }

    // Finally, remember the current state for next time
    bcopy(&_stylus, &_oldStylus, sizeof(self.stylus));
    bcopy(&buttonState, &oldButtonState, sizeof(buttonState));
}

//////////////////////////////////////////////////////////////
#pragma mark posting events
//////////////////////////////////////////////////////////////


- (void)postNXEventwithType:(int)eventType subType:(SInt16)eventSubType otherButton:(UInt8)otherButton
{
    static NXEventData eventData;
    eventData.proximity.pointerType = NX_TABLET_POINTER_PEN;
    eventData.proximity.capabilityMask = NX_TABLET_CAPABILITY_PRESSUREMASK;

    switch (eventType)
    {
        case NX_OMOUSEUP:
        case NX_OMOUSEDOWN:
            eventData.mouse.click = 0;
            eventData.mouse.buttonNumber = otherButton;
            break;


        case NX_LMOUSEDOWN:
        case NX_RMOUSEDOWN:
        case NX_RMOUSEUP:
        case NX_LMOUSEUP:
            eventData.mouse.pressure = 0;
            eventData.mouse.subType = eventSubType;
            eventData.mouse.subx = 0;
            eventData.mouse.suby = 0;
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

        case NX_MOUSEMOVED:
        case NX_LMOUSEDRAGGED:
        case NX_RMOUSEDRAGGED:
            bcopy(&_stylus.proximity, &eventData.mouse.tablet.proximity, sizeof(_stylus.proximity));
            bcopy(&_stylus.proximity, &eventData.mouseMove.tablet.proximity, sizeof(_stylus.proximity));

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

    eventData.mouseMove.tablet.point.tangentialPressure = 1;
    eventData.mouseMove.tablet.point.pressure = 1;// stylus.pressure * 20000;

    bcopy(&_stylus.proximity, &eventData.mouse.tablet.proximity, sizeof(_stylus.proximity));
    bcopy(&_stylus.proximity, &eventData.mouseMove.tablet.proximity, sizeof(_stylus.proximity));
    NSLog(@">>>>>>eventdata.pressure %d cap mask %d", eventData.mouseMove.tablet.point.pressure, eventData.mouseMove.tablet.proximity.capabilityMask);

    // Generate the tablet event to the system event driver
    IOGPoint newPoint = {_stylus.scrPos.x, _stylus.scrPos.y};
    (void) IOHIDPostEvent(self.gEventDriver, eventType, newPoint, &eventData, kNXEventDataVersion, 0, kIOHIDSetCursorPosition);

    // we always post a proximity event individually
    if (eventSubType == NX_SUBTYPE_TABLET_PROXIMITY)
    {
        NSLog(@"[POST] Proximity Event %d Subtype %d", NX_TABLETPROXIMITY, NX_SUBTYPE_TABLET_PROXIMITY);
        bcopy(&_stylus.proximity, &eventData.proximity, sizeof(NXTabletProximityData));
        (void) IOHIDPostEvent(self.gEventDriver, NX_TABLETPROXIMITY, newPoint, &eventData, kNXEventDataVersion, 0, 0);
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
- (void)setTabletMapping:(CGRect const)tabletMapping
{
    float x = (tabletMapping.origin.x != -1) ? tabletMapping.origin.x : 0;
    float y = (tabletMapping.origin.y != -1) ? tabletMapping.origin.y : 0;
    float w = (tabletMapping.size.width != -1) ? (tabletMapping.size.width - tabletMapping.origin.x + 1) : 6000;
    float h = (tabletMapping.size.height != -1) ? (tabletMapping.size.height - tabletMapping.origin.y + 1) : 4500;
    _tabletMapping = CGRectMake(x, y, w, h);
}

@end