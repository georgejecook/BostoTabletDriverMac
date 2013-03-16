//
//  BTAppDelegate.m
//  BostoTablet
//
//  Created by George Cook on 03/15/13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//

#import "BTAppDelegate.h"
#import "BTDriverManager.h"

@implementation BTAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    NSLog(@"created driver manager %@", [BTDriverManager shared]);

}

@end