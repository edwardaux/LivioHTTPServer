/**
 * This library is covered under the BSD 2-clause license below.
 * Software License Agreement (BSD License)
 *
 * ------------------------------------------------------------
 *
 * Copyright (c) 2011, Deusty, LLC
 * All rights reserved.
 *
 * Redistribution and use of this software in source and binary forms,
 * with or without modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above
 *   copyright notice, this list of conditions and the
 *   following disclaimer.
 *
 * * Neither the name of Deusty nor the names of its
 *   contributors may be used to endorse or promote products
 *   derived from this software without specific prior
 *   written permission of Deusty, LLC.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * ------------------------------------------------------------
 *
 * This library was forked from it's original version, which can be found here: https://github.com/robbiehanson/CocoaHTTPServer
 * This library retains it's original license and is maintained by Livio.
 */

//
//  LivioHTTPServer.h
//  LivioHTTPServer
//
//  Created by Joel Fischer on 2/25/15.
//  Copyright (c) 2015 livio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

//! Project version number for LivioHTTPServer-Mac.
FOUNDATION_EXPORT double LivioHTTPServer_MacVersionNumber;

//! Project version string for LivioHTTPServer-Mac.
FOUNDATION_EXPORT const unsigned char LivioHTTPServer_MacVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <LivioHTTPServer_Mac/PublicHeader.h>

// MIME
#import "LHSMultipartFormDataParser.h"
#import "LHSMultipartMessageHeader.h"
#import "LHSMultipartMessageHeaderField.h"

// Responses
#import "LHSAsyncFileResponse.h"
#import "LHSDataResponse.h"
#import "LHSDynamicFileResponse.h"
#import "LHSErrorResponse.h"
#import "LHSFileResponse.h"
#import "LHSRedirectResponse.h"

// Requests
#import "LHSAuthenticationRequest.h"

// Server
#import "LHSConnection.h"
#import "LHSConnectionConfig.h"
#import "LHSMessage.h"
#import "LHSServer.h"
#import "LHSWebSocket.h"
#import "LHSWebSocketDelegate.h"
