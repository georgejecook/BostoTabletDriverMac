//
// Created by georgecook on 07/04/2013.
//
//  Copyright (c) 2012 Twin Technologies LLC. All rights reserved.
//
#import <IOKit/graphics/IOGraphicsLib.h>
#import "NSScreen+BTAdditions.h"


@implementation NSScreen (BTAdditions)

- (NSString *)screenName
{
    NSNumber *screenNumber = self.deviceDescription[@"NSScreenNumber"];
    CGDirectDisplayID displayID = [screenNumber intValue];

    NSString *screenName = nil;

    NSDictionary *deviceInfo = (__bridge_transfer NSDictionary *)IODisplayCreateInfoDictionary(CGDisplayIOServicePort(displayID), kIODisplayOnlyPreferredName);
    NSDictionary *localizedNames = [deviceInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];

    if ([localizedNames count] > 0) {
    	screenName = [localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]];
    }

    return screenName;
}

@end