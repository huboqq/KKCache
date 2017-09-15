//
//  KKDiskCache.h
//  KKCache
//
//  Created by hubo on 2017/8/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KKCacheProtocol.h"

typedef NS_ENUM(NSUInteger, kDiskCachePriority) {
    kDiskCachePriorityDefault,
    kDiskCachePriorityHigh,
    kDiskCachePriorityLow,
    kDiskCachePriorityBackground
};

@interface KKDiskCache : NSObject<KKCacheProtocol>

@property (readonly) NSString *name;
@property (readonly) NSURL *cacheURL;
@property (readonly) NSUInteger byteCount;

@property (assign) NSUInteger byteLimt;
@property (assign) NSTimeInterval ageLimt;

@property (copy) BOOL (^customArchiveBlock)(id object, NSURL *fileURL);
@property (copy) id (^customUnarchiveBlock)(NSURL *fileURL);
@property (copy) NSString *(^customCacheFileNameBlock)(NSString *key);
@property (copy) NSString *(^cacheKeyFilterBlock)(NSString *key);

- (instancetype)init NS_UNAVAILABLE;
+ (void)emptyTrash;
- (void)lockFileAccessWhileExecutingBlock:(void (^)(id<KKCacheProtocol> cache))block;
- (void)updateFileAccessDateForKey:(NSString *)key;

@end
