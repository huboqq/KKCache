//
//  KKCache.h
//  KKCache
//
//  Created by hubo on 2017/8/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KKCacheProtocol.h"
#import "KKDiskCache.h"
#import "KKMemoryCache.h"

@interface KKCache : NSObject<KKCacheProtocol>

@property (nonatomic, assign) NSUInteger byteLimt;
@property (nonatomic, assign) NSTimeInterval ageLimt;

@property (nonatomic, strong, readonly) KKDiskCache *diskCache;
@property (nonatomic, strong, readonly) KKMemoryCache *memoryCache;
@property (nonatomic, copy) NSString *(^cacheKeyFilterBlock)(NSString *key);

- (instancetype)init NS_UNAVAILABLE;
@end
