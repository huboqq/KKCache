//
//  KKMemoryCache.m
//  KKCache
//
//  Created by hubo on 2017/8/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import "KKMemoryCache.h"
#import <CommonCrypto/CommonCrypto.h>
#import <pthread.h>

@interface KKLinkedNode : NSObject
{
    @package
    NSString *_key;
    id _value;
    NSUInteger _cost;
    NSDate *_date;
    KKLinkedNode *_prev;
    KKLinkedNode *_next;
}

@end

@implementation KKLinkedNode

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KKLinkedMap : NSObject
{
    @package
    KKLinkedNode *_trailNode;
    KKLinkedNode *_headNode;
    NSMutableDictionary *_nodeDic;
    NSUInteger _totalCost;
}

- (void)bringNodeToHead:(KKLinkedNode *)node;
- (void)addNodeAtHead:(KKLinkedNode *)node;

- (void)insertNode:(KKLinkedNode *)newNode beforeNode:(KKLinkedNode *)node;
- (void)insertNode:(KKLinkedNode *)newNode afterNode:(KKLinkedNode *)node;

- (void)removeNodeForKey:(id)key;
- (void)removeTrailNode;
- (void)removeAllNodes;

@end

@implementation KKLinkedMap

- (instancetype)init {
    self = [super init];
    if (self) {
        
        _nodeDic = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)bringNodeToHead:(KKLinkedNode *)node {
    
    if ([node isEqual:_headNode] || !node) {
        return;
    }
    
    if ([node isEqual:_trailNode]) {
        
        _trailNode = node ->_prev;
        _trailNode ->_next = nil;
    } else {
        
        node ->_prev ->_next = node ->_next;
        node ->_next ->_prev = node ->_prev
        ;
    }
    
    _headNode ->_prev = node;
    node ->_next = _headNode;
    node ->_prev = nil;
    
    _headNode = node;
    
    node ->_date = [[NSDate alloc] init];
}

- (void)addNodeAtHead:(KKLinkedNode *)node {
    
    if (!node) {
        return;
    }
    
    if (_headNode) {
        _headNode ->_prev = node;
        node ->_next = _headNode;
        node->_prev = nil;
        _headNode = node;
    } else {
        _headNode = _trailNode = node;
    }
    
    node->_date = [[NSDate alloc] init];
    _totalCost += node->_cost;
    [_nodeDic setObject:node forKey:node->_key];
}

- (void)insertNode:(KKLinkedNode *)newNode beforeNode:(KKLinkedNode *)node {
    
    if (!node) {
        return;
    }
    
    if ([node isEqual:_headNode]) {
        [self addNodeAtHead:node];
    } else {
        node->_prev->_next = newNode;
        newNode->_prev = node->_prev;
        
        node->_prev = newNode;
        newNode->_next = node;
    }
    
    node->_date = [[NSDate alloc] init];
    _totalCost += newNode->_cost;
}

- (void)insertNode:(KKLinkedNode *)newNode afterNode:(KKLinkedNode *)node {
    
    if (!node) {
        return;
    }
    
    if ([node isEqual:_trailNode]) {
        _trailNode = node;
    } else {
        node->_next->_prev = newNode;
        newNode->_next = node->_next;
    }
    
    newNode->_prev = node;
    node->_next = newNode;
}

- (void)removeNodeForKey:(id)key {
    
    if (!key) {
        return;
    }
    
    KKLinkedNode *node = [_nodeDic objectForKey:key];
    if (!node) {
        return;
    }
    
    _totalCost -= node->_cost;
    
    if ([node isEqual:_headNode]) {
        if (_headNode == _trailNode) {
            _headNode = _trailNode = nil;
        } else {
            _headNode = node->_next;
            node->_next->_prev = nil;
        }
    } else if ([node isEqual:_trailNode]) {
        _trailNode = node->_prev;
        node->_prev->_next = nil;
    } else {
        node->_prev->_next = node->_next;
        node->_next->_prev = node->_prev;
    }
    [_nodeDic removeObjectForKey:key];
    node = nil;
}

- (void)removeTrailNode {
    
    if (!_trailNode) {
        return;
    }
    KKLinkedNode *node = _trailNode;
    [_nodeDic removeObjectForKey:_trailNode->_key];
    
    _totalCost -= _trailNode->_cost;
    
    if ([_trailNode isEqual:_headNode]) {
        
        _trailNode = _headNode = nil;
    } else {
        
        _trailNode = _trailNode->_prev;
        _trailNode->_next = nil;
    }
    node = nil;
}

- (void)removeAllNodes {
    
    NSDictionary *nodeDic = [_nodeDic copy];
    for (id key in [nodeDic allKeys]) {
        [self removeNodeForKey:key];
    }
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KKMemoryCache ()
{
    KKLinkedMap *_lruMap;
    KKLinkedMap *_fifoMap;
    pthread_mutex_t _lock;
    dispatch_queue_t _asyncQueue;
}

@end

@implementation KKMemoryCache

- (void)dealloc {
    
    [self unregisterNotification];
}

- (instancetype)init {
    
    self = [super init];
    if (self) {
        
        NSString *queueName = [NSString stringWithFormat:@"%@.%@",@"come.nice.kmemory.queue",NSStringFromClass([self class])];
       _asyncQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _lruMap = [[KKLinkedMap alloc] init];
        _fifoMap = [[KKLinkedMap alloc] init];
        _removeAllObjectsOnMemoryWarning = YES;
        _removeAllObjectsOnEnterBackground = NO;
        
        [self initialLock];
        
        [self registerNotification];
    }
    return self;
}

- (id)cacheKey:(id)key {
    
    if (_keyFilterBlock) {
        key = _keyFilterBlock(key);
    }
    return key;
}

- (NSDate *)date {
    return [[NSDate alloc] init];
}

#pragma mark - Async

- (void)setObject:(id)object forKey:(id)key block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
       KKCACHE_CHECK_WEAK_SELF
        [strongSelf setObject:object forKey:key];
        
        if (block) {
            block(strongSelf, key, object);
        }
    });
}

- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf setObject:object forKey:key cost:cost];
        
        if (block) {
            block(strongSelf, key, object);
        }
    });
}

- (void)objectForKey:(id)key block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        id object = [strongSelf objectForKey:key];
        
        if (block) {
            block(strongSelf, key, object);
        }
    });
}

- (void)removeObjectForKey:(id)key block:(void (^)(id<KKCacheProtocol>, NSString *, id))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf removeObjectForKey:key];
        
        if (block) {
            block(strongSelf, key, nil);
        }
    });
}

- (void)trimToDate:(NSDate *)date block:(void (^)(id<KKCacheProtocol>))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToDate:date];
        
        if (block) {
            block(strongSelf);
        }
    });
}

- (void)trimToSize:(NSUInteger)size block:(void (^)(id<KKCacheProtocol>))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToSize:size];
        
        if (block) {
            block(strongSelf);
        }
    });
}

- (void)trimToCostByDateWithLRU:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol>))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToCostByDateWithLRU:cost];
        
        if (block) {
            block(strongSelf);
        }
    });
}

- (void)trimToCostByDateWithFIFO:(NSUInteger)cost block:(void (^)(id<KKCacheProtocol>))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToCostByDateWithFIFO:cost];
        
        if (block) {
            block(strongSelf);
        }
    });
}

- (void)removeAllObjects:(void (^)(id<KKCacheProtocol>))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf removeAllObjects];
        
        if (block) {
            block(strongSelf);
        }
    });
}

#pragma mark - Sync

- (void)setObject:(id)object forKey:(id)key {
    [self setObject:object forKey:key cost:0];
}

- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost {
    
    if (!object || !key) {
        return;
    }
    
    NSUInteger costLimitLRU = 0;
    NSUInteger costLimitFIFO = 0;
    [self lock];
    costLimitLRU = _costLimtLRU;
    costLimitFIFO = _costLimtFIFO;
    [self unlock];
    
    id cacheKey = [self cacheKey:key];
    
    [self lock];
    KKLinkedNode *lruNode = [_lruMap ->_nodeDic objectForKey:cacheKey];
    KKLinkedNode *fifoNode = [_fifoMap ->_nodeDic objectForKey:cacheKey];
    [self unlock];
    
    if (!lruNode && !fifoNode) {
        
        [self lock];
        KKLinkedNode *node = [[KKLinkedNode alloc] init];
        node->_cost = cost;
        node->_key = cacheKey;
        node->_value = object;
        [_fifoMap addNodeAtHead:node];
        [self unlock];
    } else if (lruNode && !fifoNode) {
        
        [self lock];
        _lruMap ->_totalCost -= lruNode->_cost;
        
        lruNode->_cost = cost;
        [_lruMap bringNodeToHead:lruNode];
        [self unlock];
    } else if (!lruNode && fifoNode) {
        
        [self lock];
        fifoNode->_cost = cost;
        
        [_fifoMap removeNodeForKey:cacheKey];
        [_lruMap addNodeAtHead:fifoNode];
        [self unlock];
    }
    
    if (costLimitLRU > 0) {
        [self trimToCostByDateWithLRU:costLimitLRU];
    }
    
    if (costLimitFIFO > 0) {
        [self trimToCostByDateWithFIFO:costLimitFIFO];
    }
}

- (id)objectForKey:(id)key {
    
    if (!key) {
        return nil;
    }
    
    id cacheKey = [self cacheKey:key];
    
    [self lock];
    KKLinkedNode *lruNode = [_lruMap ->_nodeDic objectForKey:cacheKey];
    KKLinkedNode *fifoNode = [_fifoMap ->_nodeDic objectForKey:cacheKey];
    [self unlock];
    
    if (lruNode) {
        
        [self lock];
        [_lruMap bringNodeToHead:lruNode];
        [self unlock];
        return lruNode ->_value;
        
    } else if (fifoNode) {
        
        [self lock];
        [_fifoMap removeNodeForKey:cacheKey];
        [_lruMap addNodeAtHead:fifoNode];
        [self unlock];
        return fifoNode ->_value;
    }
    
    return nil;
}

- (void)removeObjectForKey:(id)key {
    
    if (!key) return;
    
    id cacheKey = [self cacheKey:key];
    id object = nil;

    [self lock];
    KKLinkedNode *lruNode = [_lruMap ->_nodeDic objectForKey:cacheKey];
    KKLinkedNode *fifoNode = [_fifoMap ->_nodeDic objectForKey:cacheKey];
    [self unlock];
    
    if (lruNode) {
        
        [self lock];
        object = lruNode->_value;
        [_lruMap removeNodeForKey:cacheKey];
        [self unlock];
    } else if (fifoNode) {
        
        [self lock];
        object = fifoNode->_value;
        [_fifoMap removeNodeForKey:cacheKey];
        [self unlock];
    }
}

- (void)trimToDate:(NSDate *)date {
    
    if (!date) {
        return;
    }
    
    if ([date isEqualToDate:[NSDate distantPast]]) {
        [self lock];
        [self removeAllObjects];
        [self unlock];
        return;
    }
    
    BOOL lruFinish = NO;
    while (!lruFinish) {
        
        if ([self trylock] == 0) {
            
            if (_lruMap ->_trailNode && [_lruMap ->_trailNode->_date compare:date] == NSOrderedDescending) {
                
                [_lruMap removeTrailNode];
            } else {
                
                lruFinish = YES;
            }
            [self unlock];
        } else {
            
            usleep(10 *1000);//10 ms
        }
    }
    
    BOOL fifoFinish = NO;
    while (!fifoFinish) {
        
        if ([self trylock] == 0) {
            
            if (_fifoMap ->_trailNode && [_fifoMap ->_trailNode->_date compare:date] == NSOrderedDescending) {
                
                [_fifoMap removeTrailNode];
            } else {
                
                fifoFinish = YES;
            }
            [self unlock];
        } else {
            
            usleep(10 *1000);//10 ms
        }
    }
}

- (void)trimToCost:(NSUInteger)cost {
    
}

- (void)trimToCostByDateWithLRU:(NSUInteger)cost {
    
    if (cost < _lruMap ->_totalCost) {
        
        BOOL finish = NO;
        while (!finish) {
            if ([self trylock] == 0) {
                
                if (_lruMap ->_trailNode && cost < _lruMap ->_totalCost) {
                    [_lruMap removeTrailNode];
                } else {
                    finish = YES;
                }
                [self unlock];
            } else {
                sleep(10 *1000);
            }
        }

    }
    
}

- (void)trimToCostByDateWithFIFO:(NSUInteger)cost {
    
    if (cost < _fifoMap ->_totalCost) {
        
        BOOL finish = NO;
        while (!finish) {
            
            if ([self trylock] == 0) {
                
                if (_fifoMap ->_trailNode && cost < _fifoMap ->_totalCost) {
                    [_fifoMap removeTrailNode];
                } else {
                    finish = YES;
                }
                [self unlock];
            } else {
                sleep(10 *1000);
            }
        }
    }
}

- (void)removeAllObjects {
    
    [self lock];
    [_lruMap removeAllNodes];
    [_fifoMap removeAllNodes];
    [self unlock];
}

#pragma mark - Notification

- (void)registerNotification {
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification object:[UIApplication sharedApplication]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];
}

- (void)unregisterNotification {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidReceiveMemoryWarningNotification
                                                  object:[UIApplication sharedApplication]];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidEnterBackgroundNotification
                                                  object:[UIApplication sharedApplication]];
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    
    if (_removeAllObjectsOnMemoryWarning) {
        
        [self removeAllObjects:nil];
    }
}

- (void)didEnterBackground:(NSNotification *)notification {
    
    if (_removeAllObjectsOnEnterBackground) {
        
        [self removeAllObjects:nil];
    }
}

#pragma mark - Lock

- (void)initialLock {
    
    pthread_mutex_init(&_lock, NULL);
}

- (void)lock {
    
    pthread_mutex_lock(&_lock);
}

- (int)trylock {
    
    return pthread_mutex_trylock(&_lock);
}

- (void)unlock {
    
    pthread_mutex_unlock(&_lock);
}

@end
