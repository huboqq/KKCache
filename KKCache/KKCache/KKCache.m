//
//  KKCache.m
//  KKCache
//
//  Created by hubo on 2017/8/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import "KKCache.h"

NSString *const kCachePrefix = @"nice.come.kcache";

@interface KKCache ()
{
    dispatch_queue_t _asyncQueue;
}

@property (nonatomic, strong) KKDiskCache *diskCache;
@property (nonatomic, strong) KKMemoryCache *memoryCache;

@end

@implementation KKCache

- (instancetype)init {
    @throw [NSException exceptionWithName:@"Must initialize with a name" reason:@"Must initialize with a name，use -initWithName：" userInfo:nil];
    return [super init];
}

- (instancetype)shareInstance {
    
    static KKCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        cache = [self initWithName:[NSString stringWithFormat:@"%@.%@",kCachePrefix,NSStringFromClass([self class])]];
    });
    return cache;
}

- (instancetype)initWithName:(NSString *)name {
    
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath {
    
    return [self initWithName:name prefix:kCachePrefix rootPath:rootPath];
}

- (instancetype)initWithName:(NSString *)name prefix:(NSString *)prefix rootPath:(NSString *)rootPath {
    
    self = [super init];
    if (self) {
        
        _memoryCache = [[KKMemoryCache alloc] init];
        _diskCache = [[KKDiskCache alloc] initWithName:name prefix:prefix rootPath:rootPath];
        KKCACHE_DECL_WEAK_SELF
        _diskCache.cacheKeyFilterBlock = ^NSString *(NSString *key) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return nil;
            }
            return strongSelf.cacheKeyFilterBlock(key);
        };
        
        NSString *queueName = [NSString stringWithFormat:@"%@.%@",prefix,NSStringFromClass([self class])];
        _asyncQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

#pragma mark - Async

- (void)setObject:(id)object forKey:(NSString *)key block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    [self setObject:object forKey:key cost:0 block:block];
}

- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block {
    
    if (block) {
        
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        [_memoryCache setObject:object forKey:key cost:cost block:^(KKMemoryCache *cache, NSString *key, id value) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_enter(group);
        [_diskCache setObject:object forKey:key block:^(id<KKCacheProtocol> cache, NSString *key, id value) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_notify(group, _asyncQueue, ^{
            block(self, key, object);
        });
    } else {
        
        [self setObject:object forKey:key];
    }
}

- (void)objectForKey:(NSString *)key block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    if (!key) return;
    
    if (block) {
        
        dispatch_async(_asyncQueue, ^{
            
            KKCACHE_DECL_WEAK_SELF
            [_memoryCache objectForKey:key block:^(KKMemoryCache *cache, NSString *key, id value) {
                
                KKCACHE_CHECK_WEAK_SELF
                if (!strongSelf) {
                    return;
                }
                if (value) {
                    
                    [strongSelf ->_diskCache updateFileAccessDateForKey:key];
                    
                    dispatch_async(strongSelf ->_asyncQueue, ^{
                        block(strongSelf, key, value);
                    });
                } else {
                    
                    [strongSelf ->_diskCache objectForKey:key block:^(id<KKCacheProtocol> cache, NSString *key, id value) {
                        
                        if ([value isKindOfClass:[UIImage class]]) {
                            
                            UIImage *image = (UIImage *)value;
                            [strongSelf -> _memoryCache setObject:image forKey:key cost:image.size.width * image.size.height * 3 block:nil];
                        } else {
                            [strongSelf ->_memoryCache setObject:value forKey:key block:nil];
                        }
                        
                        KKCACHE_DECL_WEAK_SELF
                        dispatch_async(strongSelf ->_asyncQueue, ^{
                            
                            KKCACHE_CHECK_WEAK_SELF
                            if (!strongSelf) {
                                return;
                            }
                            block(strongSelf, key, value);
                        });
                        
                    }];
                }
            }];
        });
    } else  {
        
        id object = [self objectForKey:key];
        block(self, key, object);
    }
}

- (void)removeObjectForKey:(NSString *)key block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    if (!key) return;
    
    if (block) {
        
        __block id object = nil;
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        [self ->_memoryCache removeObjectForKey:key block:^(KKMemoryCache *cache, NSString *key, id value) {
            if (object) object = value;
            dispatch_group_leave(group);
        }];
        
        dispatch_group_enter(group);
        [self ->_diskCache removeObjectForKey:key block:^(id<KKCacheProtocol> cache, NSString *key, id value) {
            if (object) object = value;
            dispatch_group_leave(group);
        }];
        
        dispatch_group_notify(group, _asyncQueue, ^{
            block(self, key, object);
        });
        
    } else {
        
        [self removeObjectForKey:key];
    }
}

- (void)trimToDate:(NSDate *)date block:(void (^)(id<KKCacheProtocol>))block {
    
    if (block) {
        
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        [_memoryCache trimToDate:date block:^(KKMemoryCache *cache) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_enter(group);
        [_diskCache trimToDate:date block:^(id<KKCacheProtocol> cache) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_notify(group, _asyncQueue, ^{
            block(self);
        });
    } else {
        
        [self trimToDate:date];
    }
}

- (void)trimToSizeByDate:(NSUInteger)size block:(void (^)(id<KKCacheProtocol>))block {
    
    if (block) {
        
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        [_memoryCache trimToSizeByDate:size block:^(id<KKCacheProtocol> cache) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_enter(group);
        [_diskCache trimToSizeByDate:size block:^(id<KKCacheProtocol> cache) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_notify(group, _asyncQueue, ^{
            block(self);
        });
    } else {
        [self trimToSizeByDate:size];
    }
}

- (void)removeAllObjects:(void (^)(id<KKCacheProtocol>))block {
    
    if (block) {
        
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_enter(group);
        [_memoryCache removeAllObjects:^(id<KKCacheProtocol> cache) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_enter(group);
        [_diskCache removeAllObjects:^(id<KKCacheProtocol> cache) {
            dispatch_group_leave(group);
        }];
        
        dispatch_group_notify(group, _asyncQueue, ^{
            block(self);
        });
    }
}

#pragma mark - Sync

- (void)setObject:(id)object forKey:(NSString *)key {
    
    [self setObject:object forKey:key cost:0];
}

- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost {
    
    [_memoryCache setObject:object forKey:key cost:cost];
    [_diskCache setObject:object forKey:key];
}

- (id)objectForKey:(NSString *)key {
    
    id object = [_memoryCache objectForKey:key];
    if (!object) {
        object = [_diskCache objectForKey:key];
    }
    return object;
}

- (void)removeObjectForKey:(NSString *)key {
    
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key];
}

- (void)trimToDate:(NSDate *)date {
    
    [_memoryCache trimToDate:date];
    [_diskCache trimToDate:date];
}

- (void)trimToSize:(NSUInteger)size {
    
    [_memoryCache trimToSize:size];
    [_diskCache trimToSize:size];
}

- (void)trimToSizeByDate:(NSUInteger)size {
    
    [_memoryCache trimToSizeByDate:size];
    [_diskCache trimToSizeByDate:size];
}

- (void)removeAllObjects {
    
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjects];
}

#pragma mark - Properties

- (void)setByteLimt:(NSUInteger)byteLimt {
    _byteLimt = byteLimt;
    [_diskCache setByteLimt:byteLimt];
}

- (void)setAgeLimt:(NSTimeInterval)ageLimt {
    _ageLimt = ageLimt;
    [_diskCache setAgeLimt:ageLimt];
}

@end
