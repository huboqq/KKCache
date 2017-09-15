//
//  ViewController.m
//  KKCache
//
//  Created by hubo on 2017/9/7.
//  Copyright © 2017年 nice. All rights reserved.
//

#import "ViewController.h"
#import "KKDiskCache.h"

@interface ViewController ()
{
    KKDiskCache *_diskCache;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
 
    NSMutableData *dataValue = [NSMutableData new]; // 32KB
    for (int i = 0; i < 100* 100 * 1024; i++) {
        [dataValue appendBytes:&i length:1];
    }
    
    _diskCache = [[KKDiskCache alloc] initWithName:@"test"];
    
//    for (int i = 0; i < 30000; i++) {
//        [_diskCache setObject:dataValue forKey:[NSString stringWithFormat:@"hu--%d",i]];
//        NSLog(@"hubo --- %d",i);
//    }
    
    NSString *rootPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSURL *url = [NSURL fileURLWithPathComponents:@[rootPath, @"test"]];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
        NSError *error = nil;
       BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:[url path] withIntermediateDirectories:YES attributes:nil error:&error];
        if (success) {
//            for (int i = 0; i < 30000; i++) {
//                NSURL *cacheUrl = [url URLByAppendingPathComponent:[NSString stringWithFormat:@"hu--%d",i]];
//                BOOL su = [NSKeyedArchiver archiveRootObject:dataValue toFile:[cacheUrl path]];
//                NSLog(@"hubo -- %d --- %d",su,i);
//            }
        }
    }
    
    for (int i = 0; i < 30000; i++) {
        NSURL *cacheUrl = [url URLByAppendingPathComponent:[NSString stringWithFormat:@"hu--%d",i]];
        BOOL su = [NSKeyedArchiver archiveRootObject:dataValue toFile:[cacheUrl path]];
//        BOOL su = [dataValue writeToFile:[cacheUrl path] atomically:NO];
        NSLog(@"hubo -- %d --- %d",su,i);
    }

}


@end
