//
//  MCHttpResponse.m
//  SJMediaCacheServer
//
//  Created by 畅三江 on 2025/3/9.
//

#import "MCHttpResponse.h"
#import "MCSProxyTask.h"
#import "MCTcpSocketServer.h"
#import "MCHttpRequest.h"
#import "MCHttpRequestRange.h"
#import "MCPin.h"
#import "MCSMimeType.h"

@interface MCHttpResponse ()<MCSProxyTaskDelegate>
- (void)_finishResponse;
- (void)_sendFinalData:(dispatch_data_t _Nullable)content;
- (NSString *)_resourceTypeForPathExtension:(NSString *)pathExtension;
- (void)_reportProxyTaskCompletionWithError:(NSError *_Nullable)error;
@end

@implementation MCHttpResponse {
    MCTcpSocketConnection *mConnection;
    MCSProxyTask *mTask;
    id mStrongSelf;
    BOOL mHeaderHasSent;
    BOOL mSending;
    BOOL mClosed;
    BOOL mProxyTaskStarted;
    BOOL mProxyTaskFinished;
    NSInteger mResponseStatusCode;
    int64_t mResponseByteCount;
    NSString *mResourceType;
    NSString *mRequestPathExtension;
}

+ (void)processConnection:(MCTcpSocketConnection *)connection {
    [MCHttpResponse httpResponseWithConnection:connection];
}

+ (instancetype)httpResponseWithConnection:(MCTcpSocketConnection *)connection {
    return [MCHttpResponse.alloc initWithConnection:connection];
}

- (instancetype)initWithConnection:(MCTcpSocketConnection *)connection {
    self = [super init];
    mConnection = connection;
    mStrongSelf = self;
    
    __weak typeof(self) _self = self;
    connection.onStateChange = ^(MCTcpSocketConnection * _Nonnull connection, nw_connection_state_t state, nw_error_t  _Nullable error) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self _connectionStateDidChange:state error:error];
    };
    [connection start];
    return self;
}

#ifdef SJDEBUG
- (void)dealloc {
    NSLog(@"%@<%p>: %d : %s", NSStringFromClass(self.class), self, __LINE__, sel_getName(_cmd));
}
#endif

- (void)_connectionStateDidChange:(nw_connection_state_t)state error:(nw_error_t _Nullable)error {
    if ( mClosed ) {
        return;
    }
    
    switch (state) {
        case nw_connection_state_waiting:
        case nw_connection_state_preparing:
            break;
        case nw_connection_state_ready: {
            [self _receiveData];
        }
            break;
        case nw_connection_state_invalid:
        case nw_connection_state_failed:
        case nw_connection_state_cancelled: {
            [self _close];
        }
            break;
    }
}

- (void)_receiveData {
    __weak typeof(self) _self = self;
    [mConnection receiveDataWithMinimumIncompleteLength:1 maximumLength:4 * 1024 * 1024 completion:^(dispatch_data_t  _Nullable content, nw_content_context_t  _Nullable context, _Bool is_complete, nw_error_t  _Nullable err) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        if ( err ) {
            [self _closeConnectionWithError:@"Data receive failed."];
            return;
        }
        
        if ( self->mClosed ) {
            return;
        }
        
        [self _processRequestWithData:content];
    }];
}

- (void)_closeConnectionWithError:(NSString * _Nullable)desc {
    (void)desc;
    if ( mHeaderHasSent || mSending ) {
        [self _close];
        return;
    }

    NSMutableString *message = [NSMutableString.alloc init];
    [message appendString:@"HTTP/1.1 502 Bad Gateway\r\n"];
    [message appendString:@"Content-Length: 0\r\n"];
    [message appendString:@"Connection: close\r\n"];
    [message appendString:@"\r\n"];

    mSending = YES;
    dispatch_data_t content = [mConnection createDataWithString:message];
    __weak typeof(self) _self = self;
    [mConnection sendData:content context:NW_CONNECTION_FINAL_MESSAGE_CONTEXT isComplete:YES completion:^(nw_error_t  _Nullable error) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        if ( error ) {
            [self _close];
        }
        else {
            [self _finishResponse];
        }
    }];
}

- (void)_finishResponse {
    if ( mClosed ) {
        return;
    }

    // NW_CONNECTION_FINAL_MESSAGE_CONTEXT has already sent TCP FIN. Releasing
    // the response here keeps the successful write-close intact; cancelling the
    // connection would turn a complete small HLS response into error -1005.
    mClosed = YES;
    if ( mTask ) {
        [mTask close];
        mTask = nil;
    }
    [self _reportProxyTaskCompletionWithError:nil];
    mConnection.onStateChange = nil;
    mStrongSelf = nil;
}

- (void)_close {
    if ( mClosed ) {
        return;
    }
    
    mClosed = YES;
    if ( mTask ) {
        [mTask close];
        mTask = nil;
    }
    [mConnection close];
    mStrongSelf = nil;
}

- (void)_processRequestWithData:(dispatch_data_t)content {
    NSError *error = nil;
    MCHttpRequest *req = [MCHttpRequest parseRequestWithData:content error:&error];
    if ( req == nil ) {
        [self _closeConnectionWithError:error.userInfo[NSLocalizedDescriptionKey]];
        return;
    }
    
    if ( [MCPin isPinReq:req] ) {
        [self _sendPinResponse];
        return;
    }
    
    NSString *range = req.headers[@"Range"];
    if ( range ) {
        if ( ![MCHttpRequestRange parseRequestRangeWithHeader:range error:&error] ) {
            [self _closeConnectionWithError:error.userInfo[NSLocalizedDescriptionKey]];
            return;
        }
    }
    
    NSString *host = req.headers[@"Host"];
    NSString *target = req.requestTarget;
    NSString *url = [NSString stringWithFormat:@"http://%@%@", host, target];
    NSMutableURLRequest *proxyRequest = [NSMutableURLRequest.alloc initWithURL:[NSURL URLWithString:url]];
    mRequestPathExtension = proxyRequest.URL.path.pathExtension.lowercaseString;
    mResourceType = [self _resourceTypeForPathExtension:mRequestPathExtension];
    mProxyTaskStarted = YES;
    if ( MCSProxyTask.eventHandler != nil ) {
        MCSProxyTask.eventHandler(YES, mResourceType, 0, 0, nil);
    }
    
    NSMutableDictionary<NSString *, NSString *> *headers = [req.headers mutableCopy];
    [headers removeObjectForKey:@"Host"];
    [headers removeObjectForKey:@"User-Agent"];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        [proxyRequest setValue:obj forHTTPHeaderField:key];
    }];
    
    mTask = [MCSProxyTask.alloc initWithRequest:proxyRequest delegate:self];
    [mTask prepare];
}

#pragma mark - MCSProxyTaskDelegate

- (void)task:(id<MCSProxyTask>)task didReceiveResponse:(id<MCSResponse>)response {
    dispatch_async(mConnection.queue, ^{
        [self _onDataSendable];
    });
}

- (void)task:(id<MCSProxyTask>)task hasAvailableDataWithLength:(NSUInteger)length {
    dispatch_async(mConnection.queue, ^{
        [self _onDataSendable];
    });
}

- (void)task:(id<MCSProxyTask>)task didAbortWithError:(nullable NSError *)error {
    dispatch_async(mConnection.queue, ^{
        [self _reportProxyTaskCompletionWithError:error];
        if ( !self->mHeaderHasSent && !self->mSending ) {
            [self _closeConnectionWithError:nil];
        }
        else {
            [self _close];
        }
    });
}

#pragma mark - name

- (void)_onDataSendable {
    if ( mSending || mClosed ) {
        return;
    }
    
    if ( mTask.isAborted ) {
        return;
    }
    
    if ( !mHeaderHasSent ) {
        if ( !mTask.response ) {
            return;
        }
        
        mSending = YES;
        id<MCSResponse> response = mTask.response;
        BOOL isPartialResponse = response.totalLength != NSUIntegerMax &&
            (response.range.location != 0 || response.range.length < response.totalLength);
        mResponseStatusCode = isPartialResponse ? 206 : 200;
        mResponseByteCount = response.range.length <= INT64_MAX ? (int64_t)response.range.length : 0;
        NSString *contentType = response.contentType;
        if ( contentType.length == 0 || [contentType isEqualToString:@"application/octet-stream"] ) {
            contentType = MCSMimeType(mRequestPathExtension);
        }
        NSMutableString *message = [NSMutableString.alloc init];
        // 206
        if ( isPartialResponse ) {
            [message appendString:@"HTTP/1.1 206 Partial Content\r\n"];
            [message appendString:@"Server: localhost\r\n"];
            [message appendFormat:@"Content-Type: %@\r\n", contentType ?: @"application/octet-stream"];
            [message appendString:@"Accept-Ranges: bytes\r\n"];
            [message appendFormat:@"Content-Range: bytes %lu-%lu/%lu\r\n", response.range.location, NSMaxRange(response.range) - 1, response.totalLength];
            [message appendFormat:@"Content-Length: %lu\r\n", response.range.length];
            [message appendString:@"Connection: close\r\n"];
            [message appendString:@"\r\n"];
        }
        // 200
        else {
            [message appendString:@"HTTP/1.1 200 OK\r\n"];
            [message appendString:@"Server: localhost\r\n"];
            [message appendFormat:@"Content-Type: %@\r\n", contentType ?: @"application/octet-stream"];
            [message appendString:@"Accept-Ranges: bytes\r\n"];
            if ( response.totalLength != NSUIntegerMax ) {
                [message appendFormat:@"Content-Length: %lu\r\n", response.totalLength];
            }
            [message appendString:@"Connection: close\r\n"];
            [message appendString:@"\r\n"];
        }
        dispatch_data_t content = [mConnection createDataWithString:message];
        __weak typeof(self) _self = self;
        [mConnection sendData:content context:NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT isComplete:NO completion:^(nw_error_t  _Nullable error) {
            __strong typeof(_self) self = _self;
            if ( self == nil ) return;
            self->mHeaderHasSent = error == nil;
            [self _onDataSendCompleteWithError:error];
        }];
        
        return; // return;
    }
    
    NSData *data = [mTask readDataOfLength:8 * 1024];
    if ( data.length == 0 ) {
        // A small HLS resource (for example an EXT-X-MAP init segment) can be
        // completely downloaded before the socket queue gets its first send
        // callback. Do not close before draining the reader: doing so aborts
        // the loopback response and AVPlayer reports NSURLErrorNetworkConnectionLost.
        if ( mTask.isDone ) {
            [self _sendFinalData:nil];
        }
        return;
    }

    dispatch_data_t content = [mConnection createData:data];
    if ( mTask.isDone ) {
        [self _sendFinalData:content];
        return;
    }

    mSending = YES;
    __weak typeof(self) _self = self;
    [mConnection sendData:content context:NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT isComplete:NO completion:^(nw_error_t  _Nullable error) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self _onDataSendCompleteWithError:error];
    }];
}

- (void)_sendFinalData:(dispatch_data_t _Nullable)content {
    mSending = YES;
    __weak typeof(self) _self = self;
    [mConnection sendData:content context:NW_CONNECTION_FINAL_MESSAGE_CONTEXT isComplete:YES completion:^(nw_error_t  _Nullable error) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        if ( error ) {
            [self _close];
        }
        else {
            [self _finishResponse];
        }
    }];
}

- (void)_onDataSendCompleteWithError:(nw_error_t _Nullable)error {
    if ( error ) {
        [self _close];
        return;
    }
    
    dispatch_async(self->mConnection.queue, ^{
        self->mSending = NO;
        [self _onDataSendable];
    });
}

- (NSString *)_resourceTypeForPathExtension:(NSString *)pathExtension {
    if ( [pathExtension isEqualToString:@"m3u8"] ) return @"playlist";
    if ( [pathExtension isEqualToString:@"ts"] || [pathExtension isEqualToString:@"m4s"] ) return @"media";
    if ( [pathExtension isEqualToString:@"init"] || [pathExtension isEqualToString:@"mp4"] ) return @"initialization";
    if ( [pathExtension isEqualToString:@"key"] ) return @"key";
    if ( [pathExtension isEqualToString:@"vtt"] ) return @"subtitle";
    return @"other";
}

- (void)_reportProxyTaskCompletionWithError:(NSError *_Nullable)error {
    if ( !mProxyTaskStarted || mProxyTaskFinished ) return;
    mProxyTaskFinished = YES;
    if ( MCSProxyTask.eventHandler != nil ) {
        MCSProxyTask.eventHandler(NO, mResourceType ?: @"other", mResponseStatusCode, mResponseByteCount, error);
    }
}

- (void)_sendPinResponse {
    NSString *message = @"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    dispatch_data_t content = [mConnection createDataWithString:message];
    __weak typeof(self) _self = self;
    [mConnection sendData:content context:NW_CONNECTION_FINAL_MESSAGE_CONTEXT isComplete:YES completion:^(nw_error_t  _Nullable error) {
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        if ( error ) {
            [self _close];
        }
        else {
            [self _finishResponse];
        }
    }];
}
@end
