//
//  KKCacheProtocol.h
//  KKCache
//
//  Created by hubo on 2017/8/22.
//  Copyright © 2017年 nice. All rights reserved.
//

#import <Foundation/Foundation.h>

#define KKCACHE_DECL_WEAK_SELF __weak typeof(self) weakSelf = self;
#define KKCACHE_CHECK_WEAK_SELF __strong typeof(weakSelf) strongSelf = weakSelf;if(!strongSelf) return;

@protocol KKCacheProtocol <NSObject>

@optional
+ (instancetype)shareInstance;
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath;
- (instancetype)initWithName:(NSString *)name prefix:(NSString *)prefix rootPath:(NSString *)rootPath;

#pragma mark - Async

- (void)setObject:(id)object forKey:(NSString *)key block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block;
- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block;
- (void)objectForKey:(NSString *)key block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block;

- (void)removeObjectForKey:(NSString *)key block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block;
- (void)trimToDate:(NSDate *)date block:(void (^)(id<KKCacheProtocol> cache))block;
- (void)trimToSize:(NSUInteger)size block:(void (^)(id<KKCacheProtocol> cache))block;
- (void)trimToSizeByDate:(NSUInteger)size block:(void (^)(id<KKCacheProtocol> cache))block;
- (void)removeAllObjects:(void (^)(id<KKCacheProtocol> cache))block;

#pragma mark - Sync

- (void)setObject:(id)object forKey:(NSString *)key;
- (id)objectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key;
- (void)trimToDate:(NSDate *)date;
- (void)trimToSize:(NSUInteger)size;
- (void)trimToSizeByDate:(NSUInteger)size;
- (void)removeAllObjects;

@end
