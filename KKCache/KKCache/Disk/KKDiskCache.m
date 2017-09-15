//
//  KKDiskCache.m
//  KKCache
//
//  Created by hubo on 2017/8/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import "KKDiskCache.h"
#import <CommonCrypto/CommonCrypto.h>
#import "KKBackgroundTask.h"

#define KKDiskCacheError(error) if (error) { NSLog(@"%@ (%d) ERROR: %@", \
[[NSString stringWithUTF8String:__FILE__] lastPathComponent], \
__LINE__, [error localizedDescription]); }

NSString *const kDiskCacheDefaultName = @"kDiskCacheDefaultName";
NSString *const kDiskCachePrefix = @"come.nice.KKDiskCache";

static NSString *KKNSStringMD5(NSString *string) {
    if (!string) return nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],  result[1],  result[2],  result[3],
            result[4],  result[5],  result[6],  result[7],
            result[8],  result[9],  result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

@interface KKDiskCache ()

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *cacheURL;
@property (assign) NSUInteger byteCount;

@property (nonatomic, strong) dispatch_queue_t asyncQueue;
@property (nonatomic, strong) dispatch_semaphore_t lockSemaphore;

@property (nonatomic, strong) NSMutableDictionary *sizes;
@property (nonatomic, strong) NSMutableDictionary *dates;

@end

@implementation KKDiskCache

@synthesize byteLimt = _byteLimt;
@synthesize ageLimt = _ageLimt;

@synthesize customArchiveBlock = _customArchiveBlock;
@synthesize customUnarchiveBlock = _customUnarchiveBlock;
@synthesize customCacheFileNameBlock = _customCacheFileNameBlock;
@synthesize cacheKeyFilterBlock = _cacheKeyFilterBlock;

- (instancetype)init {
    @throw [NSException exceptionWithName:@"Must initialize with a name" reason:@"Must initialize with a name，use -initWithName：" userInfo:nil];
    return [super init];
}

+ (instancetype)shareInstance {
    
    static KKDiskCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[self alloc] initWithName:kDiskCacheDefaultName];
    });
    return cache;
}

- (instancetype)initWithName:(NSString *)name {
    
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)rootPath {
    
    return [self initWithName:name prefix:kDiskCachePrefix rootPath:rootPath];
}

- (instancetype)initWithName:(NSString *)name prefix:(NSString *)prefix rootPath:(NSString *)rootPath {
    
    self = [super init];
    if (self) {
        
        _lockSemaphore = dispatch_semaphore_create(1);
        
        NSString *queueName = [NSString stringWithFormat:@"%@.%p",kDiskCachePrefix,self];
        _asyncQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _byteLimt = 0;
        _ageLimt = 0;
        _byteCount = 0;
        
        _name = name;
        
        _dates = [NSMutableDictionary dictionary];
        _sizes = [NSMutableDictionary dictionary];
        
        NSString *pathComponents = [NSString stringWithFormat:@"%@",_name];
        _cacheURL = [NSURL fileURLWithPathComponents:@[rootPath,pathComponents, prefix]];
        
        [self creatCacheDirectory];
        [self initializeDiskProperties];
    }
    
    return self;
}

#pragma mark - Private Method Initialize

- (BOOL)creatCacheDirectory {
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[_cacheURL path]]) {
        return NO;
    }
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtURL:_cacheURL
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
    KKDiskCacheError(error);
    return success;
}

- (void)initializeDiskProperties {
    
    NSUInteger byteCount = 0;
    NSArray *keys = @[NSURLContentModificationDateKey, NSURLTotalFileSizeKey];
    
    NSError *error = nil;
    
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_cacheURL
                                                   includingPropertiesForKeys:keys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:&error];
    KKDiskCacheError(error);
    
    for (NSURL *fileURL in files) {
        
        NSString *key = [self keyForFileURL:fileURL];
        
        NSError *error = nil;
        NSDictionary *dictionary = [fileURL resourceValuesForKeys:keys error:&error];
        KKDiskCacheError(error);
        
        NSDate *date = [dictionary objectForKey:NSURLContentModificationDateKey];
        if (date && key) {
            [_dates setObject:date forKey:key];
        }
        
        NSNumber *fileSize = [dictionary objectForKey:NSURLTotalFileSizeKey];
        if (fileSize && key) {
            [_sizes setObject:fileSize forKey:key];
            byteCount += [fileSize unsignedIntegerValue];
        }
    }
    
    if (byteCount > 0) {
        self.byteCount = byteCount;
    }
    
}

#pragma mark - Private Methods

- (NSURL *)fileURLForKey:(NSString *)key {
    
    if (key.length <= 0) {
        return nil;
    }
    return [_cacheURL URLByAppendingPathComponent:[self cacheKeyWithKey:key]];
}

- (NSURL *)fileURLForCacheKey:(NSString *)cacheKey {
    
    if (cacheKey.length <= 0) {
        return nil;
    }
    return [_cacheURL URLByAppendingPathComponent:cacheKey];
}

- (NSString * _Nonnull)cacheKeyWithKey:(NSString *)key {
    
    if (!key) {
        return @"";
    }
    
    if (_customCacheFileNameBlock) {
        key = _customCacheFileNameBlock(key);
    }
    
    if (_cacheKeyFilterBlock) {
        key = _cacheKeyFilterBlock(key);
    }
    
    return KKNSStringMD5(key);
}

- (NSString * _Nonnull)keyForFileURL:(NSURL *)fileURL {
    
    NSString *lastPathComponet = [fileURL lastPathComponent];
    return lastPathComponet?:@"";
}

- (BOOL)writeToFileWithObject:(id)object fileURL:(NSURL *)fileURL {
    
    BOOL success = NO;
    NSString *path = [fileURL path];
    if (_customArchiveBlock) {
        
        success = _customArchiveBlock(object, fileURL);
    } else {
        
        NSData *data = nil;
        if ([object isKindOfClass:[NSData class]]) {
            data = (NSData *)object;
        } else {
            data = [NSKeyedArchiver archivedDataWithRootObject:object];
        }
        [data writeToFile:path atomically:NO];
    }
    return success;
}

- (BOOL)setFileModificationDate:(NSDate *)date fileURL:(NSURL *)fileURL {
    
    if (!date || !fileURL) {
        return NO;
    }
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:date}
                                                    ofItemAtPath:[fileURL path]
                                                           error:&error];
    
    
    if (success) {
        NSString *cacheKey = [self keyForFileURL:fileURL];
        if (cacheKey) {
            
         [_dates setObject:date forKey:cacheKey];
        }
    }
    
    return success;
}

- (void)updateFileAccessDateForKey:(NSString *)key {
    
    if (!key) return;
    
    NSURL *fileURL = [self fileURLForKey:key];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        [self lock];
        [self setFileModificationDate:[self date] fileURL:fileURL];
        [self unLock];
    }
}

- (NSDate *)date {
    return [[NSDate alloc] init];
}

- (BOOL)removeFileAndExcuteBlockForKey:(NSString *)key {
    
    NSURL *fileURL = [self fileURLForCacheKey:key];
    if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        return NO;
    }
    
    BOOL success = [KKDiskCache moveItemAtURLToTrash:fileURL];
    if (!success) {
        return NO;
    }
    [KKDiskCache emptyTrash];
    
    NSNumber *size = [_sizes objectForKey:key];
    if (size) {
        self.byteCount -= [size unsignedIntegerValue];
    }
    [_sizes removeObjectForKey:key];
    [_dates removeObjectForKey:key];
    
    return YES;
}

#pragma mark - Async

- (void)setObject:(id)object forKey:(NSString *)key block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf setObject:object forKey:key];
        
        if (block) {
            [strongSelf lock];
            block(strongSelf, key, object);
            [strongSelf unLock];
        }
    });
}

- (void)objectForKey:(NSString *)key block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        id object = [strongSelf objectForKey:key];
        if (block) {
            [strongSelf lock];
            block(strongSelf, key, object);
            [strongSelf unLock];
        }
    });
}

- (void)removeObjectForKey:(NSString *)key block:(void (^)(id<KKCacheProtocol> cache, NSString *key, id value))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf removeObjectForKey:key];
        
        if (block) {
            [strongSelf lock];
            block(strongSelf, key, nil);
            [strongSelf unLock];
        }
        
    });
}

- (void)trimToDate:(NSDate *)date block:(void (^)(id<KKCacheProtocol> cache))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToDate:date];
        
        if (block) {
            [strongSelf lock];
            block(strongSelf);
            [strongSelf unLock];
        }
    });
}

- (void)trimToSize:(NSUInteger)size block:(void (^)(id<KKCacheProtocol> cache))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToSize:size];
        
        if (block) {
            [strongSelf lock];
            block(strongSelf);
            [strongSelf unLock];
        }
    });
}

- (void)trimToSizeByDate:(NSUInteger)size block:(void (^)(id<KKCacheProtocol> cache))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf trimToSizeByDate:size];
        
        if (block) {
            [strongSelf lock];
            block(strongSelf);
            [strongSelf unLock];
        }
    });
}

- (void)removeAllObjects:(void (^)(id<KKCacheProtocol> cache))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        [strongSelf removeAllObjects];
        
        if (block) {
            [strongSelf lock];
            block(strongSelf);
            [strongSelf unLock];
        }
    });
}

- (void)lockFileAccessWhileExecutingBlock:(void (^)(id<KKCacheProtocol> cache))block {
    
    KKCACHE_DECL_WEAK_SELF
    dispatch_async(_asyncQueue, ^{
        
        KKCACHE_CHECK_WEAK_SELF
        
        if (block) {
            [strongSelf lock];
            block(strongSelf);
            [strongSelf unLock];
        }
        
    });
}

#pragma mark - Sync

- (void)setObject:(id)object forKey:(NSString *)key {
    
    if (!object || !key) {
        return;
    }
    
    NSDate *date = [self date];
    KKBackgroundTask *task = [KKBackgroundTask start];
    
    [self lock];
    NSURL *fileURL = [self fileURLForKey:key];
    BOOL success = [self writeToFileWithObject:object fileURL:fileURL];
    if (success) {
        [self setFileModificationDate:date fileURL:fileURL];
        
        NSArray *keys = @[NSURLTotalFileSizeKey];
        NSError *error = nil;
        NSDictionary *dictionary = [fileURL resourceValuesForKeys:keys error:&error];
        KKDiskCacheError(error);
        
        NSNumber *fileSize = [dictionary objectForKey:NSURLTotalFileSizeKey];
        if (fileSize) {
            NSString *cacheKey = [self cacheKeyWithKey:key];
            NSNumber *prevFileSize = [_sizes objectForKey:cacheKey];
            if (prevFileSize) {
                self.byteCount -= [prevFileSize unsignedIntegerValue];
            }
            self.byteCount += [fileSize unsignedIntegerValue]; //atomic
            [_sizes setObject:fileSize forKey:cacheKey];
            
            if (self ->_byteLimt > 0 && self ->_byteCount > self ->_byteLimt) {
                [self trimToSizeByDate:self ->_byteLimt block:nil];
            }
            
            if (_ageLimt > 0) {
                [self trimToDate:[NSDate dateWithTimeIntervalSinceNow:_ageLimt] block:nil];
            }
            
        }
    }
    [self unLock];
    [task end];
}

- (id)objectForKey:(NSString *)key {
    
    id object = nil;
    NSDate *date = [self date];
    
    [self lock];
    NSURL *fileURL = [self fileURLForKey:key];
    NSString *path = [fileURL path];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        
        [self setFileModificationDate:date fileURL:fileURL];
        
        if (self.customUnarchiveBlock) {
            object = self.customUnarchiveBlock(fileURL);
        } else {
            NSData *data = [NSData dataWithContentsOfFile:path];
            object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if (data && !object) {
                object = data;
            }

        }
    }
    
    [self unLock];
    
    return object;
}

- (void)removeObjectForKey:(NSString *)key {
    
    if (!key) {
        return;
    }
    
    KKBackgroundTask *task = [KKBackgroundTask start];
    [self lock];
    [self removeFileAndExcuteBlockForKey:[self cacheKeyWithKey:key]];
    [self unLock];
    [task end];
    
}

- (void)trimToDate:(NSDate *)date {
    
    if (!date) {
        return;
    }
    
    if ([date isEqual:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    KKBackgroundTask *task = [KKBackgroundTask start];
    [self lock];
    [self trimDiskTodate:date];
    [self unLock];
    [task end];
}

- (void)trimToSize:(NSUInteger)size {
    
    if (size == 0) {
        [self removeAllObjects];
        return;
    }
    
    KKBackgroundTask *task = [KKBackgroundTask start];
    [self lock];
    [self trimToDiskSize:size];
    [self unLock];
    [task end];
}

- (void)trimToSizeByDate:(NSUInteger)size {
    
    if (size == 0) {
        [self removeAllObjects];
        return;
    }
    
    KKBackgroundTask *task = [KKBackgroundTask start];
    [self lock];
    [self trimDiskSizeTodate:size];
    [self unLock];
    [task end];
}

- (void)trimToDiskSize:(NSUInteger)trimSize {
    
    NSArray *keysSortedByValue = [_sizes keysSortedByValueUsingSelector:@selector(compare:)];
    for (NSString *cacheKey in keysSortedByValue) {
        
        [self removeFileAndExcuteBlockForKey:cacheKey];
        
        if (self.byteCount <= trimSize) {
            break;
        }
    }
}

- (void)trimDiskTodate:(NSDate *)trimDate {
    
    NSArray *keysSortedByValue = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    for (NSString *cacheKey in keysSortedByValue) {
        
        NSDate *date = [_dates objectForKey:cacheKey];
        
        if (!date) {
            continue;
        }
        
        if ([date compare:trimDate] == NSOrderedDescending) {
            [self removeFileAndExcuteBlockForKey:cacheKey];
        } else {
            break;
        }
    }
}

- (void)trimDiskSizeTodate:(NSUInteger)trimSize {
    
    NSArray *keysSortedByValue = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    for (NSString *cacheKey in keysSortedByValue) {
        
        [self removeFileAndExcuteBlockForKey:cacheKey];
        if (self.byteCount < trimSize *.5f) {
            break;
        }
    }
}

- (void)removeAllObjects {
    
    KKBackgroundTask *task = [KKBackgroundTask start];
    [self lock];
    
    [KKDiskCache moveItemAtURLToTrash:_cacheURL];
    self.byteCount = 0;
    [KKDiskCache emptyTrash];
    [self creatCacheDirectory];
    
    [self unLock];
    [task end];
}

#pragma mark - Private Method Trash

+ (dispatch_queue_t)shareEmptyTrashQueue {
    
    static dispatch_queue_t emptyTrashQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *queueName = [NSString stringWithFormat:@"%@.trash",kDiskCachePrefix];
        emptyTrashQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(emptyTrashQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    });
    return emptyTrashQueue;
}

+ (NSURL *)shareTrahEmptyURL {
    
    static NSURL *trashURL = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        trashURL = [[[NSURL alloc] initFileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:kDiskCachePrefix isDirectory:YES];
        if (![[NSFileManager defaultManager] fileExistsAtPath:[trashURL path]]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtURL:trashURL
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&error];
            KKDiskCacheError(error);
        }
    });
    return trashURL;
}

+ (BOOL)moveItemAtURLToTrash:(NSURL *)itemURL {
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[itemURL path]]) {
        return NO;
    }
    
    NSString *uniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
    NSURL *uniqueTrashURL = [[KKDiskCache shareTrahEmptyURL] URLByAppendingPathComponent:uniqueString];
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] moveItemAtPath:[itemURL path] toPath:[uniqueTrashURL path] error:&error];
    KKDiskCacheError(error);
    
    return success;
}

+ (void)emptyTrash {
    
    KKBackgroundTask *task = [KKBackgroundTask start];
    
    dispatch_async([self shareEmptyTrashQueue], ^{
        
        NSError *error = nil;
        NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self shareTrahEmptyURL]
                                      includingPropertiesForKeys:nil
                                                         options:0
                                                           error:&error];
        KKDiskCacheError(error);
        
        for (NSURL *fileURL in items) {
            NSError *removeItemsError = nil;
            [[NSFileManager defaultManager] removeItemAtPath:[fileURL path] error:&removeItemsError];
            KKDiskCacheError(removeItemsError);
        }
        
        [task end];
    });
}

#pragma mark - Lock

- (void)lock {
    dispatch_semaphore_wait(_lockSemaphore, DISPATCH_TIME_FOREVER);
}

- (void)unLock {
    dispatch_semaphore_signal(_lockSemaphore);
}

#pragma mark - Properties

- (void)setByteLimt:(NSUInteger)byteLimt {
    
    [self lock];
    _byteLimt = byteLimt;
    [self unLock];
}

- (NSUInteger)byteLimt {
    
    NSUInteger byteLimt = 0;
    
    [self lock];
    byteLimt = _byteLimt;
    [self unLock];
    
    return byteLimt;
}

- (void)setAgeLimt:(NSTimeInterval)ageLimt {
    
    [self lock];
    _ageLimt = ageLimt;
    [self unLock];
}

- (NSTimeInterval)ageLimt {
    
    NSTimeInterval ageLimt = .0;
    
    [self lock];
    ageLimt = _ageLimt;
    [self unLock];
    
    return ageLimt;
}

@end
