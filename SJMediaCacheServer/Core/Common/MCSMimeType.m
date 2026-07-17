//
//  MCSMimeType.m
//  SJMediaCacheServer
//
//  Created by db on 2024/10/16.
//

#import "MCSMimeType.h"
#import <TargetConditionals.h>

#if TARGET_OS_IOS
#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

FOUNDATION_EXPORT NSString *
MCSMimeTypeFromFileAtPath(NSString *path) {
    return MCSMimeType(path.pathExtension);
}

FOUNDATION_EXPORT NSString *
MCSMimeType(NSString *filenameExtension) {
    if ( filenameExtension == nil ) filenameExtension = @"";
    NSString *mimeType = nil;
#if TARGET_OS_IOS
    if ( @available(iOS 14.0, *) ) {
        UTType *type = [UTType typeWithFilenameExtension:filenameExtension];
        mimeType = [type preferredMIMEType];
    }
    else {
        CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)filenameExtension, NULL);
        if ( type != NULL) {
            CFStringRef ref = UTTypeCopyPreferredTagWithClass(type, kUTTagClassMIMEType);
            CFRelease(type);
            if ( ref != NULL ) mimeType = (__bridge_transfer NSString *)ref;
        }
    }
#endif
    
    if ( mimeType == nil ) {
        static NSDictionary<NSString *, NSString *> *commonMimeTypes;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            commonMimeTypes = @{
                @"m3u8": @"application/vnd.apple.mpegurl",
                @"ts": @"video/mp2t",
                @"m4s": @"video/iso.segment",
                @"mp4": @"video/mp4",
                @"m4a": @"audio/mp4",
                @"aac": @"audio/aac",
                @"vtt": @"text/vtt",
                @"key": @"application/octet-stream",
                @"default_mime_type": @"application/octet-stream"
            };
        });
        // 如果没有找到对应的MIME类型，返回默认类型
        mimeType = commonMimeTypes[filenameExtension] ?: commonMimeTypes[@"default_mime_type"];
    }
    return mimeType;
}
