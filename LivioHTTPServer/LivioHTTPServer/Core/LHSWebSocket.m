
#import "LHSWebSocket.h"
#import "LHSMessage.h"
#import <SuperSocket/SuperSocket.h>
#import "NSNumber+LHSNumber.h"
#import "NSData+LHSData.h"

NSString *const LHSWebSocketDidDieNotification  = @"LHSWebSocketDidDie";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

static NSInteger const LHSTimeoutNone = -1;
static NSInteger const LHSTimeoutRequestBody = 10;

static NSInteger const LHSTagHTTPRequestBody = 100;
static NSInteger const LHSTagHTTPResponseHeaders = 200;
static NSInteger const LHSTagHTTPResponseBody = 201;

static NSInteger const LHSTagPrefix = 300;
static NSInteger const LHSTagMessagePlusSuffix = 301;
static NSInteger const LHSTagMessageWithLength = 302;
static NSInteger const LHSTagMessageMaskingKey = 303;
static NSInteger const LHSTagPayloadPrefix = 304;
static NSInteger const LHSTagPayloadLength = 305;
static NSInteger const LHSTagPayloadLength16 = 306;
static NSInteger const LHSTagPayloadLength64 = 307;

static Byte const LHSWebSocketContinuationFrame = 0;
static Byte const LHSWebSocketTextFrame = 1;
static Byte const LHSWebSocketBinaryFrame = 2;
static Byte const LHSWebSocketConnectionClose = 8;
static Byte const LHSWebSocketPing = 9;
static Byte const LHSWebSocketPong = 10;

static inline BOOL WS_OP_IS_FINAL_FRAGMENT(UInt8 frame) {
    return (frame & 0x80) ? YES : NO;
}

static inline BOOL WS_PAYLOAD_IS_MASKED(UInt8 frame) {
    return (frame & 0x80) ? YES : NO;
}

static inline NSUInteger WS_PAYLOAD_LENGTH(UInt8 frame) {
    return frame & 0x7F;
}

#pragma clang diagnostic pop


@interface LHSWebSocket () <STCPSocketDelegate>

- (void)readRequestBody;
- (void)sendResponseBody:(NSData *)bodyData;
- (void)sendResponseHeaders;

@end


#pragma mark -

@implementation LHSWebSocket {
    BOOL nextFrameMasked;
    NSUInteger nextOpCode;
    NSData *maskingKey;
}

@synthesize delegate;

+ (BOOL)isWebSocketRequest:(LHSMessage *)request {
    // Request (Draft 75):
    //
    // GET /demo HTTP/1.1
    // Upgrade: WebSocket
    // Connection: Upgrade
    // Host: example.com
    // Origin: http://example.com
    // WebSocket-Protocol: sample
    //
    //
    // Request (Draft 76):
    //
    // GET /demo HTTP/1.1
    // Upgrade: WebSocket
    // Connection: Upgrade
    // Host: example.com
    // Origin: http://example.com
    // Sec-WebSocket-Protocol: sample
    // Sec-WebSocket-Key1: 4 @1  46546xW%0l 1 5
    // Sec-WebSocket-Key2: 12998 5 Y3 1  .P00
    //
    // ^n:ds[4U
    
    // Look for Upgrade: and Connection: headers.
    // If we find them, and they have the proper value,
    // we can safely assume this is a websocket request.
    
    NSString *upgradeHeaderValue = [request headerField:@"Upgrade"];
    NSString *connectionHeaderValue = [request headerField:@"Connection"];
    
    BOOL isWebSocket = YES;
    
    if (!upgradeHeaderValue || !connectionHeaderValue) {
        isWebSocket = NO;
    } else if (![upgradeHeaderValue caseInsensitiveCompare:@"WebSocket"] == NSOrderedSame) {
        isWebSocket = NO;
    } else if ([connectionHeaderValue rangeOfString:@"Upgrade" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        isWebSocket = NO;
    }
    
    //	HTTPLogTrace2(@"%@: %@ - %@", __FILE__, THIS_METHOD, (isWebSocket ? @"YES" : @"NO"));
    
    return isWebSocket;
}


#pragma mark Setup and Teardown

@synthesize websocketQueue;

- (id)initWithRequest:(LHSMessage *)aRequest socket:(STCPSocket *)socket {
    // HTTPLogTrace();
    
    if (aRequest == nil) {
        return nil;
    }
    
    if ((self = [super init])) {
        //		if (HTTP_LOG_VERBOSE)
        //		{
        //			NSData *requestHeaders = [aRequest messageData];
        //
        //			NSString *temp = [[NSString alloc] initWithData:requestHeaders encoding:NSUTF8StringEncoding];
        //			// HTTPLogVerbose(@"%@[%p] Request Headers:\n%@", __FILE__, self, temp);
        //		}
        
        websocketQueue = dispatch_queue_create("com.livio.httpserver.websocket", NULL);
        request = aRequest;
        
        asyncSocket = socket;
        [asyncSocket setDelegate:self delegateQueue:websocketQueue];
        
        term = [[NSData alloc] initWithBytes:"\xFF" length:1];
    }
    return self;
}

- (void)dealloc {
    // HTTPLogTrace();
    
    [asyncSocket setDelegate:nil delegateQueue:NULL];
    [asyncSocket disconnect];
}

- (id<LHSWebSocketDelegate>)delegate {
    __block id result = nil;
    
    dispatch_sync(websocketQueue, ^{
        result = delegate;
    });
    
    return result;
}

- (void)setDelegate:(id<LHSWebSocketDelegate>)aDelegate {
    dispatch_async(websocketQueue, ^{
        delegate = aDelegate;
    });
}


#pragma mark Start and Stop

/**
 * Starting point for the WebSocket after it has been fully initialized (including subclasses).
 * This method is called by the HTTPConnection it is spawned from.
 **/
- (void)start {
    // This method is not exactly designed to be overriden.
    // Subclasses are encouraged to override the didOpen method instead.
    
    dispatch_async(websocketQueue, ^{ @autoreleasepool {
        if (isStarted) {
            return;
        }
        isStarted = YES;
        
        [self sendResponseHeaders];
        [self didOpen];
    }});
}

/**
 * This method is called by the HTTPServer if it is asked to stop.
 * The server, in turn, invokes stop on each WebSocket instance.
 **/
- (void)stop {
    // This method is not exactly designed to be overriden.
    // Subclasses are encouraged to override the didClose method instead.
    
    dispatch_async(websocketQueue, ^{ @autoreleasepool {
        [asyncSocket disconnect];
    }});
}


#pragma mark HTTP Response

- (void)readRequestBody {
    // HTTPLogTrace();
    
    [asyncSocket readDataToLength:8 withTimeout:LHSTimeoutNone tag:LHSTagHTTPRequestBody];
}

- (NSString *)originResponseHeaderValue {
    // HTTPLogTrace();
    
    NSString *origin = [request headerField:@"Origin"];
    
    if (origin == nil) {
        NSString *port = [NSString stringWithFormat:@"%hu", [asyncSocket localPort]];
        
        return [NSString stringWithFormat:@"http://localhost:%@", port];
    } else {
        return origin;
    }
}

- (NSString *)locationResponseHeaderValue {
    // HTTPLogTrace();
    
    NSString *location;
    
    NSString *scheme = [asyncSocket isSecure] ? @"wss" : @"ws";
    NSString *host = [request headerField:@"Host"];
    
    NSString *requestUri = [[request url] relativeString];
    
    if (host == nil) {
        NSString *port = [NSString stringWithFormat:@"%hu", [asyncSocket localPort]];
        
        location = [NSString stringWithFormat:@"%@://localhost:%@%@", scheme, port, requestUri];
    } else {
        location = [NSString stringWithFormat:@"%@://%@%@", scheme, host, requestUri];
    }
    
    return location;
}

- (NSString *)secWebSocketKeyResponseHeaderValue {
    NSString *key = [request headerField:@"Sec-WebSocket-Key"];
    NSString *guid = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    return [[[key stringByAppendingString:guid] dataUsingEncoding:NSUTF8StringEncoding].sha1 base64EncodedStringWithOptions:kNilOptions];
}

- (void)sendResponseHeaders {
    // HTTPLogTrace();
    
    // Request (RFC6455):
    //
    // GET /demo HTTP/1.1
    // Upgrade: WebSocket
    // Connection: Upgrade
    // Host: example.com
    // Origin: http://example.com
    // Sec-WebSocket-Protocol: sample
    // Sec-WebSocket-Key: (base64, when decoded 16 bytes)
    // Sec-WebSocket-Version: 13
    
    //
    // Response (RFC6455):
    //
    // HTTP/1.1 101 Switching Protocols
    // Upgrade: websocket
    // Connection: Upgrade
    // Sec-WebSocket-Accept: (concatenate key with "258EAFA5-E914-47DA-95CA-C5AB0DC85B11", calculate SHA-1, base64 encode)
    // Sec-WebSocket-Origin: http://example.com
    // Sec-WebSocket-Location: ws://example.com/demo
    // Sec-WebSocket-Protocol: sample
    //
    // 8jKS'y:G*Co,Wxa-
    
    
    LHSMessage *wsResponse = [[LHSMessage alloc] initResponseWithStatusCode:101
                                                                description:@"Switching Protocols"
                                                                    version:HTTPVersion1_1];
    
    [wsResponse setHeaderField:@"Upgrade" value:@"websocket"];
    [wsResponse setHeaderField:@"Connection" value:@"Upgrade"];
    
    // Note: It appears that WebSocket-Origin and WebSocket-Location
    // are required for Google's Chrome implementation to work properly.
    //
    // If we don't send either header, Chrome will never report the WebSocket as open.
    // If we only send one of the two, Chrome will immediately close the WebSocket.
    //
    // In addition to this it appears that Chrome's implementation is very picky of the values of the headers.
    // They have to match exactly with what Chrome sent us or it will close the WebSocket.
    
    // TODO: Determine if still necessary
    NSString *originValue = [self originResponseHeaderValue];
    NSString *locationValue = [self locationResponseHeaderValue];
    
    NSString *originField = @"WebSocket-Origin";
    NSString *locationField = @"WebSocket-Location";
    
    [wsResponse setHeaderField:originField value:originValue];
    [wsResponse setHeaderField:locationField value:locationValue];
    
    NSString *acceptValue = [self secWebSocketKeyResponseHeaderValue];
    if (acceptValue) {
        [wsResponse setHeaderField:@"Sec-WebSocket-Accept" value:acceptValue];
    }
    
    NSData *responseHeaders = [wsResponse messageData];
    
    
    //	if (HTTP_LOG_VERBOSE)
    //	{
    //		NSString *temp = [[NSString alloc] initWithData:responseHeaders encoding:NSUTF8StringEncoding];
    //		// HTTPLogVerbose(@"%@[%p] Response Headers:\n%@", __FILE__, self, temp);
    //	}
    
    [asyncSocket writeData:responseHeaders withTimeout:LHSTimeoutNone tag:LHSTagHTTPResponseHeaders];
}

- (NSData *)processKey:(NSString *)key {
    // HTTPLogTrace();
    
    unichar c;
    NSUInteger i;
    NSUInteger length = [key length];
    
    // Concatenate the digits into a string,
    // and count the number of spaces.
    
    NSMutableString *numStr = [NSMutableString stringWithCapacity:10];
    long long numSpaces = 0;
    
    for (i = 0; i < length; i++) {
        c = [key characterAtIndex:i];
        
        if (c >= '0' && c <= '9') {
            [numStr appendFormat:@"%C", c];
        } else if (c == ' ') {
            numSpaces++;
        }
    }
    
    long long num = strtoll([numStr UTF8String], NULL, 10);
    
    long long resultHostNum;
    
    if (numSpaces == 0)
        resultHostNum = 0;
    else
        resultHostNum = num / numSpaces;
    
    // HTTPLogVerbose(@"key(%@) -> %qi / %qi = %qi", key, num, numSpaces, resultHostNum);
    
    // Convert result to 4 byte big-endian (network byte order)
    // and then convert to raw data.
    
    UInt32 result = OSSwapHostToBigInt32((uint32_t)resultHostNum);
    
    return [NSData dataWithBytes:&result length:4];
}

- (void)sendResponseBody:(NSData *)bodyData {
    // HTTPLogTrace();
    
    NSAssert([bodyData length] == 8, @"Invalid requestBody length");
    
    NSString *key1 = [request headerField:@"Sec-WebSocket-Key1"];
    NSString *key2 = [request headerField:@"Sec-WebSocket-Key2"];
    
    NSData *secKey1Data = [self processKey:key1];
    NSData *secKey2Data = [self processKey:key2];
    
    // Concatenated d1, d2 & d3
    
    NSMutableData *data = [NSMutableData dataWithCapacity:(4 + 4 + 8)];
    [data appendData:secKey1Data];
    [data appendData:secKey2Data];
    [data appendData:bodyData];
    
    // Hash the data using MD5
    
    NSData *responseBody = data.md5;
    
    [asyncSocket writeData:responseBody withTimeout:LHSTimeoutNone tag:LHSTagHTTPResponseBody];
    
    //	if (HTTP_LOG_VERBOSE)
    //	{
    //		NSString *s1 = [[NSString alloc] initWithData:d1 encoding:NSASCIIStringEncoding];
    //		NSString *s2 = [[NSString alloc] initWithData:d2 encoding:NSASCIIStringEncoding];
    //		NSString *s3 = [[NSString alloc] initWithData:d3 encoding:NSASCIIStringEncoding];
    //
    //		NSString *s0 = [[NSString alloc] initWithData:d0 encoding:NSASCIIStringEncoding];
    //
    //		NSString *sH = [[NSString alloc] initWithData:responseBody encoding:NSASCIIStringEncoding];
    //
    //		// HTTPLogVerbose(@"key1 result : raw(%@) str(%@)", d1, s1);
    //		// HTTPLogVerbose(@"key2 result : raw(%@) str(%@)", d2, s2);
    //		// HTTPLogVerbose(@"key3 passed : raw(%@) str(%@)", d3, s3);
    //		// HTTPLogVerbose(@"key0 concat : raw(%@) str(%@)", d0, s0);
    //		// HTTPLogVerbose(@"responseBody: raw(%@) str(%@)", responseBody, sH);
    //
    //	}
}


#pragma mark Core Functionality

- (void)didOpen {
    // HTTPLogTrace();
    
    // Override me to perform any custom actions once the WebSocket has been opened.
    // This method is invoked on the websocketQueue.
    //
    // Don't forget to invoke [super didOpen] in your method.
    
    // Start reading for messages
    [asyncSocket readDataToLength:1 withTimeout:LHSTimeoutNone tag:LHSTagPayloadPrefix];
    
    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(webSocketDidOpen:)]) {
        [self.delegate webSocketDidOpen:self];
    }
}

- (void)sendMessage:(NSString *)msg {
    NSData *msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
    [self sendData:msgData forOpCode:LHSWebSocketTextFrame];
}

- (void)sendBinaryData:(NSData *)msg {
    [self sendData:msg forOpCode:LHSWebSocketBinaryFrame];
}

- (void)sendData:(NSData *)msgData forOpCode:(Byte)opcode {
    // HTTPLogTrace();
    
    Byte prefix = 0x80 | opcode;
    NSMutableData *data = nil;
    NSUInteger length = msgData.length;
    
    if (length <= 125) {
        data = [NSMutableData dataWithCapacity:(length + 2)];
        [data appendBytes:&prefix length:1];
        UInt8 len = (UInt8)length;
        [data appendBytes:&len length:1];
        [data appendData:msgData];
    } else if (length <= 0xFFFF) {
        Byte extendedPrefix[2] = {prefix, 0x7E};
        data = [NSMutableData dataWithCapacity:(length + 4)];
        [data appendBytes:extendedPrefix length:2];
        UInt16 len = (UInt16)length;
        [data appendBytes:(UInt8[]) { len >> 8, len & 0xFF } length:2];
        [data appendData:msgData];
    } else {
        Byte extendedPrefix[2] = {prefix, 0x7F};
        data = [NSMutableData dataWithCapacity:(length + 10)];
        [data appendBytes:extendedPrefix length:2];
        [data appendBytes:(UInt8[]) { 0, 0, 0, 0, (UInt8)(length >> 24), (UInt8)(length >> 16), (UInt8)(length >> 8), length & 0xFF } length:8];
        [data appendData:msgData];
    }
    
    // Remember: STCPSocket is thread-safe
    [asyncSocket writeData:data withTimeout:LHSTimeoutNone tag:0];
}

- (void)didReceiveMessage:(NSString *)msg {
    // HTTPLogTrace();
    
    // Override me to process incoming messages.
    // This method is invoked on the websocketQueue.
    //
    // For completeness, you should invoke [super didReceiveMessage:msg] in your method.
    
    // Notify delegate
    NSLog(@"LHSWebSocket socket: %@ did receive message: %@", self, msg);
    if ([delegate respondsToSelector:@selector(webSocket:didReceiveMessage:)]) {
        [delegate webSocket:self didReceiveMessage:msg];
    }
}

- (void)didReceiveData:(NSData *)data {
    // HTTPLogTrace();
    
    // Override me to process incoming messages.
    // This method is invoked on the websocketQueue.
    //
    // For completeness, you should invoke [super didReceiveMessage:msg] in your method.
    
    // Notify delegate
    NSLog(@"LHSWebSocket socket: %@ did receive data: %@", self, data);
    if ([delegate respondsToSelector:@selector(webSocket:didReceiveData:)]) {
        [delegate webSocket:self didReceiveData:data];
    }
}

- (void)didClose {
    // HTTPLogTrace();
    
    // Override me to perform any cleanup when the socket is closed
    // This method is invoked on the websocketQueue.
    //
    // Don't forget to invoke [super didClose] at the end of your method.
    
    // Notify delegate
    NSLog(@"LHSWebSocket socket: %@ did close", self);
    if ([delegate respondsToSelector:@selector(webSocketDidClose:)]) {
        [delegate webSocketDidClose:self];
    }
    
    // Notify HTTPServer
    [[NSNotificationCenter defaultCenter] postNotificationName:LHSWebSocketDidDieNotification object:self];
}

#pragma mark WebSocket Frame

- (BOOL)isValidWebSocketFrame:(UInt8)frame {
    NSUInteger rsv = frame & 0x70;
    NSUInteger opcode = frame & 0x0F;
    if (rsv || (3 <= opcode && opcode <= 7) || (0xB <= opcode && opcode <= 0xF)) {
        return NO;
    }
    return YES;
}


#pragma mark SuperSocket Delegate

// 0                   1                   2                   3
// 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
// +-+-+-+-+-------+-+-------------+-------------------------------+
// |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
// |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
// |N|V|V|V|       |S|             |   (if payload len==126/127)   |
// | |1|2|3|       |K|             |                               |
// +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
// |     Extended payload length continued, if payload len == 127  |
// + - - - - - - - - - - - - - - - +-------------------------------+
// |                               |Masking-key, if MASK set to 1  |
// +-------------------------------+-------------------------------+
// | Masking-key (continued)       |          Payload Data         |
// +-------------------------------- - - - - - - - - - - - - - - - +
// :                     Payload Data continued ...                :
// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
// |                     Payload Data continued ...                |
// +---------------------------------------------------------------+

- (void)socket:(STCPSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    // HTTPLogTrace();
    NSLog(@"socket: %@ did read data: %@ with tag: %@", sock, data, @(tag));
    
    switch (tag) {
        case LHSTagHTTPRequestBody: {
            [self sendResponseHeaders];
            [self sendResponseBody:data];
            [self didOpen];
        } break;
        case LHSTagPrefix: {
            UInt8 *pFrame = (UInt8 *)[data bytes];
            UInt8 frame = *pFrame;
            
            if (frame <= 0x7F) {
                [asyncSocket readDataToData:term withTimeout:LHSTimeoutNone tag:LHSTagMessagePlusSuffix];
            } else {
                // Unsupported frame type
                [self didClose];
            }
        } break;
        case LHSTagPayloadPrefix: {
            UInt8 *pFrame = (UInt8 *)[data bytes];
            UInt8 frame = *pFrame;
            if ([self isValidWebSocketFrame:frame]) {
                nextOpCode = (frame & 0x0F);
                [asyncSocket readDataToLength:1 withTimeout:LHSTimeoutNone tag:LHSTagPayloadLength];
            } else {
                // Unsupported frame type
                [self didClose];
            }
        } break;
        case LHSTagPayloadLength: {
            UInt8 frame = *(UInt8 *)[data bytes];
            nextFrameMasked = WS_PAYLOAD_IS_MASKED(frame);
            NSUInteger length = WS_PAYLOAD_LENGTH(frame);
            maskingKey = nil;
            if (length <= 125) {
                if (nextFrameMasked) {
                    [asyncSocket readDataToLength:4 withTimeout:LHSTimeoutNone tag:LHSTagMessageMaskingKey];
                }
                [asyncSocket readDataToLength:length withTimeout:LHSTimeoutNone tag:LHSTagMessageWithLength];
            } else if (length == 126) {
                [asyncSocket readDataToLength:2 withTimeout:LHSTimeoutNone tag:LHSTagPayloadLength16];
            } else {
                [asyncSocket readDataToLength:8 withTimeout:LHSTimeoutNone tag:LHSTagPayloadLength64];
            }
        } break;
        case LHSTagPayloadLength16: {
            UInt8 *pFrame = (UInt8 *)[data bytes];
            NSUInteger length = ((NSUInteger)pFrame[0] << 8) | (NSUInteger)pFrame[1];
            
            if (nextFrameMasked) {
                [asyncSocket readDataToLength:4 withTimeout:LHSTimeoutNone tag:LHSTagMessageMaskingKey];
            }
            [asyncSocket readDataToLength:length withTimeout:LHSTimeoutNone tag:LHSTagMessageWithLength];
        } break;
        case LHSTagPayloadLength64: {
            // FIXME: 64bit data size in memory?
            NSLog(@"%s:%d Livio HTTP Server Error, cannot handle 64 bit data size", __FILE__, __LINE__);
            [self didClose];
        } break;
        case LHSTagMessageWithLength: {
            NSUInteger msgLength = [data length];
            if (nextFrameMasked && maskingKey) {
                NSMutableData *masked = data.mutableCopy;
                UInt8 *pData = (UInt8 *)masked.mutableBytes;
                UInt8 *pMask = (UInt8 *)maskingKey.bytes;
                for (NSUInteger i = 0; i < msgLength; i++) {
                    pData[i] = pData[i] ^ pMask[i % 4];
                }
                data = masked;
            }
            
            if (nextOpCode == LHSWebSocketTextFrame) {
                NSString *msg = [[NSString alloc] initWithBytes:[data bytes] length:msgLength encoding:NSUTF8StringEncoding];
                [self didReceiveMessage:msg];
            } else if (nextOpCode == LHSWebSocketBinaryFrame) {
                [self didReceiveData:data];
            } else {
                [self didClose];
                return;
            }
            
            // Read next frame
            [asyncSocket readDataToLength:1 withTimeout:LHSTimeoutNone tag:LHSTagPayloadPrefix];
        } break;
        case LHSTagMessageMaskingKey: {
            maskingKey = data.copy;
        } break;
        default: {
            NSUInteger msgLength = [data length] - 1; // Excluding ending 0xFF frame
            NSString *msg = [[NSString alloc] initWithBytes:[data bytes] length:msgLength encoding:NSUTF8StringEncoding];
            [self didReceiveMessage:msg];
            
            // Read next message
            [asyncSocket readDataToLength:1 withTimeout:LHSTimeoutNone tag:LHSTagPrefix];
        } break;
    }
}

- (void)socketDidDisconnect:(STCPSocket *)sock withError:(NSError *)error {
    //	HTTPLogTrace2(@"%@[%p]: socketDidDisconnect:withError: %@", __FILE__, self, error);
    
    [self didClose];
}

@end
