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


// taken from tablet magic
enum {
	kStylusTip			= 0,
	kStylusButton1,
	kStylusButton2,
	kStylusEraser,
	kStylusButtonTypes,
	
	kButtonLeft,			// Mouse button 1
	kButtonMiddle,			// Mouse button 3
	kButtonRight,			// Mouse button 2
	kButtonExtra,			// Mouse button 4
	kButtonSide,			// Mouse Button 5
	kButtonMax,
	
	kSystemNoButton		= 0,
	kSystemButton1,
	kSystemButton2,
	kSystemButton3,
	kSystemButton4,
	kSystemButton5,
	kSystemEraser,
	kSystemDoubleClick,
	kSystemSingleClick,
	kSystemControlClick,
	kSystemClickOrRelease,
	kSystemClickTypes,
	
	kOtherButton3		= 2,
	kOtherButton4,
	kOtherButton5,
	
	kBitStylusTip		= 1 << kStylusTip,
	kBitStylusButton1	= 1 << kStylusButton1,
	kBitStylusButton2	= 1 << kStylusButton2,
	kBitStylusEraser	= 1 << kStylusEraser,
	
	k12inches1270ppi	=	15240
};


enum {
	kToolNone		= 0,
	kToolInkingPen	= 0x0812,				// Intuos2 ink pen XP-110-00A
	kToolInkingPen2	= 0x0012,				// Inking pen
	kToolPen1		= 0x0822,				// Intuos Pen GP-300E-01H
	kToolPen2		= 0x0022,
	kToolPen3		= 0x0842,				// added from Cheng
	kToolGripPen	= 0x0852,				// Intuos2 Grip Pen XP-501E-00A
	kToolStrokePen1	= 0x0832,				// Intuos2 stroke pen XP-120-00A
	kToolStrokePen2	= 0x0032,				// Stroke pen
	kToolMouse2D	= 0x0007,				// 2D Mouse
	kToolMouse3D	= 0x009C,				// ?? Mouse (Not really sure)
	kToolMouse4D	= 0x0094,				// 4D Mouse
	kToolLens		= 0x0096,				// Lens cursor
	kToolEraser1	= 0x082A,
	kToolEraser2	= 0x085A,
	kToolEraser3	= 0x091A,
	kToolEraser4	= 0x00FA,				// Eraser
	kToolAirbrush	= 0x0112				// Airbrush
};

enum {
	kToolTypeNone = 0,
	kToolTypePen,
	kToolTypePencil,
	kToolTypeBrush,
	kToolTypeEraser,
	kToolTypeAirbrush,
	kToolTypeMouse,
	kToolTypeLens
};

typedef enum EPointerType
{
	EUnknown = 0,		// should never happen
	EPen,					// tip end of a stylus like device
	ECursor,				// any puck like device
	EEraser				// eraser end of a stylus like device
} EPointerType;

enum  {
	kRelativePointer=0x1,
	kAbsoluteStylus,
	kAbsoluteMouse,
	kMacroStylus,
	kMacroMouse
};


typedef struct MyReport {
	int16_t  proximity;
	int16_t  buttons;
	int32_t  x;
	int32_t  y;
	int32_t  pressure;
} MyReport;



typedef struct {
	CGPoint		scrPos, oldPos;			// Screen position (tracked by the tablet object)
	IOGPoint	ioPos;
	UInt8	subx,	suby;
	MyReport	report;
	struct { SInt32	x, y; } point;		// Tablet-level X / Y coordinates
	struct { SInt32	x, y; } old;		// Old coordinates used to calculate mouse mode
	struct { SInt32	x, y; } motion;		// Tablet-level X / Y motion
	struct { SInt16 x, y; } tilt;		// Current tilt, scaled for NX Event usage
	UInt16		raw_pressure;			//!< Previous raw pressure (for SD II-S ASCII)
	UInt16		pressure;				//!< Current pressure, scaled for NX Event usage
	bool		button_click;			//!< a button is clicked
	UInt16		button_mask;			//!< Bits set here for each button
	bool		button[kButtonMax];		//!< Booleans for each button
	bool		off_tablet;				//!< nothing is near or clicked
	bool		pen_near;				//!< pen or eraser is near or clicked
	bool		eraser_flag;			//!< eraser is near or clicked
	UInt16		menu_button;			//!< Last menu button pressed (clear after handling)
	
	// Intuos
	UInt16		tool;					//!< Intuos supports several tools
	int			toolid;					//!< Tool ID passed on to system for apps to recognize
	long		serialno;				//!< Serial number of the selected tool
	SInt16		rotation;				//!< Rotation from the 4D mouse
	SInt16		wheel;					//!< The 2D Mouse has a wheel
	SInt16		throttle;				//!< The mouse has a throttle (-1023 to 1023)
	
	NXTabletProximityData   proximity;  //!< Proximity data description
	
} StylusState;
