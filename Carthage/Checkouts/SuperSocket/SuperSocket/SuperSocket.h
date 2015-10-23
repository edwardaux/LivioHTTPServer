//
//  SuperSocket.h
//
//  This class is in the public domain.
//  Originally created by Joel Fischer, Livio.
//
//  Based on https://github.com/robbiehanson/CocoaAsyncSocket
//

#import <Foundation/Foundation.h>

//! Project version number for CocoaAsyncSocket.
FOUNDATION_EXPORT double SuperSocketVersionNumber;

//! Project version string for CocoaAsyncSocket.
FOUNDATION_EXPORT const unsigned char SuperSocketVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <CocoaAsyncSocket/PublicHeader.h>

#import <SuperSocket/STCPSocket.h>
#import <SuperSocket/STCPSocketDelegate.h>
#import <SuperSocket/SUDPSocket.h>
#import <SuperSocket/SUDPSocketDelegate.h>
