BostoTabletDriverMac
====================

Unofficial Tablet Driver for Bosto tablets on mac.

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
The pen works really well, and is fast and has all pressure levels. It works flawlessly with flash CS5.1, and autodesk sketchbook, and a suite of wacom test utilities.

The pen also works completely fine alongside my wacom tablet (I have both plugged in at the same time)

However, I currently have problems with Photoshop CS5.1 and Painter 12.

I have raised questions on relevant forums and I'm seeking more information on those:

* ([http://forums.adobe.com/message/5154023#5154023](http://forums.adobe.com/message/5154023#5154023))
* ([http://painterfactory.com/forums/p/5363/24126.aspx#24126](http://painterfactory.com/forums/p/5363/24126.aspx#24126))

Roadmap
------

* add better UI (hide the main window, and add status bar icon),
* add features to control pressure resistence,
* add ability to function with multiple screens,
* Refactor code to make it easier for other devs to add other bosto tablets.

Again, I'd like to say thanks to the author of tablet magic, and the Udo Killerman.
