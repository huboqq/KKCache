//
//  KKMemoryCache.h
//  KKCache
//
//  Created by hubo on 2017/8/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "KKCacheProtocol.h"

typedef NSString*(^KMemoryKeyFilterBlock)(id key);

@interface KKMemoryCache : NSObject<KKCacheProtocol>

@property (nonatomic, assign) NSUInteger costLimtFIFO;
@property (nonatomic, assign) NSUInteger costLimtLRU;
@property (nonatomic, assign) NSTimeInterval ageLimt;

@property (nonatomic, assign) BOOL removeAllObjectsOnMemoryWarning;
@property (nonatomic, assign) BOOL removeAllObjectsOnEnterBackground;

@property (nonatomic, copy) KMemoryKeyFilterBlock keyFilterBlock;

- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost;

- (void)trimToCostByDateWithLRU:(NSUInteger)cost;
- (void)trimToCostByDateWithFIFO:(NSUInteger)cost;

- (void)trimToCostByDateWithLRU:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol> cache))block;
- (void)trimToCostByDateWithFIFO:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol> cache))block;
@end
