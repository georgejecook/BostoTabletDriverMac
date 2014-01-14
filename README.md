BostoTabletDriverMac
====================
##this only works for 19mb bosto tablets.

It will not work on any other of bosto's tablest. I beleive they have a driver for their new 22 line.

##UPDATE: Release 0.5 is a mavericks compatability fix

  * Now runs on mavericks,
  * Fixes issue that caused 	

##UPDATE: Release 0.4 is ready and is looking pretty good

Installer file here: [PackageInstaller](https://github.com/georgejecook/BostoTabletDriverMac/blob/master/dist/BostoTabletDriverInstaller.pkg?raw=true) 
Run the installer, and it will install the bostoTablet driver to you /Applications folder. When you run it, you're pen should work - and you should see the monitor icon up the top in your status bar (note if you are in an application with lost of menu options, it might not appear - so you might want to alt-tab to finder, of something like that if you can't see it).

It might be that 19ma will work too.. you can always try.

###Status:

* Works on photoshop CS6, corelpainter, and other graphics apps
* It is fast, and also includes a feature to make it faster… there's a button on the settings panel which will increase the processes priority; making it faster (your admin password is required)
* can edit pressure,
* Can edit the cursor offset,
* Includes a "test pad" for testing the pen settings,
* Automatically checks if it's already running if you accidentally try to run it several times,
* Pressure is not normalized - can lead to heavy line starts/endings,
* Position is not normalized - can be quite jaggly when drawing slowly.
* Sometimes you can get a bogus line being drawn : I think it's because I screw up a mouse up event somewhere - I'll debug it over time.

The last 3 items on that list are my priority items.

Special Thanks to Udo Killermann, who is a thouroughly nice chap who made a lot of code available to me and gave me lots of advice. If I lived near you : I'd buy you a beer Udo!!


##Unofficial Tablet Driver for Bosto 19MB tablet on mac.

The bosto tablet is a wonderful cheap cintiq clone ([http://bosto-tablet.com](http://bosto-tablet.com)). However, it only has driver support for windows.

It seems sad to me that such a great tablet does not have mac support. So I decided to make one, as I'm lucky enough to be a pretty good iOS developer.

I have spent the last week or so reading up in my spare time on USB devices, and scouring source. There's not much info so I must give out a HUGE thankyou and shout out to Udo Killerman who has made the open source hyperpenproject for mac ([http://http://code.google.com/p/hyperpen-for-apple/](http://http://code.google.com/p/hyperpen-for-apple/))], which I used as a launch pad for this project.

I've had a lot of difficulties getting this tablet working: the main one has been that the HID reports that the tablet produces DO NOT match the HID descriptor. This had caused me a lot of headaches, but finally, with a lot of trial and error and some debug code which I have left in the source (but commented out) I have discovered that the report contains the following:

N.B, I have found that bits of the entire report are slightly offset, as such I create an array allBits, which contains all individiaul bits from all 8 bytes of the report.

* pressure :  report[6] | report[7] << 8;
* absolute x position : bits 15-30,
* absolute y position : bits 31-46,
* stylus tip : bit [8]
* pen button : bit [9]
* pen is on tablet : bit[12]

I did some experiments with using transactions, but I couldn't get it to work, and I figure that accessing the report is more efficient.

I also have written this in objective c (Udo's implementaiton, based on tablet magic is written in pure C). I did this as I'm going to add more settings and features to this over time (such as selecting which is the active screen, using in multiple screen setup, controlling pressure, adding better pressure algorithms), so I thought it'd be easier this way.

I have also put the enitre callback for the pen in GCD asynch blocks to get reports asap, as the report callback is a blocking callback.

Status
------


Roadmap
------

* [DONE]add better UI (hide the main window, and add status bar icon),
* [DONE]add features to control pressure resistence,
* [DONE]add ability to function with multiple screens,
* Refactor code to make it easier for other devs to add other bosto tablets.

Again, I'd like to say thanks to the author of tablet magic, and to Udo Killerman.
