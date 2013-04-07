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

//////////////////////////////////////////////////////////////
#pragma mark logging level constants
//////////////////////////////////////////////////////////////

//DO NOT CHANGE THESE

#ifndef LOGGING_LEVEL_DISABLED
#define LOGGING_LEVEL_DISABLED 0
#endif
#ifndef LOGGING_LEVEL_ERROR
#define LOGGING_LEVEL_ERROR 1
#endif
#ifndef LOGGING_LEVEL_WARN
#define LOGGING_LEVEL_WARN 2
#endif
#ifndef LOGGING_LEVEL_INFO
#define LOGGING_LEVEL_INFO 3
#endif
#ifndef LOGGING_LEVEL_VERBOSE
#define LOGGING_LEVEL_VERBOSE 4
#endif
#ifndef LOGGING_LEVEL_DEBUG
#define LOGGING_LEVEL_DEBUG 5
#endif


//////////////////////////////////////////////////////////////
#pragma mark current logging level
//////////////////////////////////////////////////////////////

/**
* set the LOGGING_LEVEL to one of the levels above
*/
//#define LOGGING_LEVEL LOGGING_LEVEL_INFO
//#define LOGGING_LEVEL LOGGING_LEVEL_VERBOSE
#define LOGGING_LEVEL LOGGING_LEVEL_DEBUG


/**
* set to 1 if you want to get the current invoking methodand line number in the log output
*/
#ifndef LOGGING_METHOD_INFO
#define LOGGING_METHOD_INFO 1
#endif

//////////////////////////////////////////////////////////////
#pragma mark logging implementation
//////////////////////////////////////////////////////////////

/**
* DO not change anything here.
*/

#define LOG_FORMAT_NO_METHOD_INFO(fmt, lvl, ...) NSLog((@"[%@] " fmt), lvl, ##__VA_ARGS__)
#define LOG_FORMAT_WITH_METHOD_INFO(fmt, lvl, ...) NSLog((@"%s[Line %d] [%@] " fmt), __PRETTY_FUNCTION__, __LINE__, lvl, ##__VA_ARGS__)

#if defined(LOGGING_METHOD_INFO) && LOGGING_METHOD_INFO
#define LOG_FORMAT(fmt, lvl, ...) LOG_FORMAT_WITH_METHOD_INFO(fmt, lvl, ##__VA_ARGS__)
#else
	#define LOG_FORMAT(fmt, lvl, ...) LOG_FORMAT_NO_METHOD_INFO(fmt, lvl, ##__VA_ARGS__)
#endif

#if defined(LOGGING_LEVEL) && LOGGING_LEVEL >= LOGGING_LEVEL_VERBOSE
#define LogVerbose(fmt, ...) LOG_FORMAT(fmt, @"verbose", ##__VA_ARGS__)
#else
	#define LogVerbose(...)
#endif

#if defined(LOGGING_LEVEL) && LOGGING_LEVEL >= LOGGING_LEVEL_INFO
#define LogInfo(fmt, ...) LOG_FORMAT(fmt, @"info", ##__VA_ARGS__)
#else
	#define LogInfo(...)
#endif

#if defined(LOGGING_LEVEL) && LOGGING_LEVEL >= LOGGING_LEVEL_WARN
#define LogWarn(fmt, ...) LOG_FORMAT(fmt, @"-warn-", ##__VA_ARGS__)
#else
	#define LogWarn(...)
#endif

#if defined(LOGGING_LEVEL) && LOGGING_LEVEL >= LOGGING_LEVEL_ERROR
#define LogError(fmt, ...) LOG_FORMAT(fmt, @"***ERROR***", ##__VA_ARGS__)
#else
	#define LogError(...)
 #endif

#if defined(LOGGING_LEVEL) && LOGGING_LEVEL >= LOGGING_LEVEL_DEBUG
	#define LogDebug(fmt, ...) LOG_FORMAT(fmt, @"DEBUG", ##__VA_ARGS__)
#else
#define LogDebug(...)
#endif

