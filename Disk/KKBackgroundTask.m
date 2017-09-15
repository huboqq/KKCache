//
//  KKBackgroundTask.m
//  KKCache
//
//  Created by hubo on 2017/8/9.
//  Copyright © 2017年 nice. All rights reserved.
//

#import "KKBackgroundTask.h"
#import <UIKit/UIKit.h>

@interface KKBackgroundTask ()

@property (nonatomic, assign) UIBackgroundTaskIdentifier taskID;

@end

@implementation KKBackgroundTask


+ (instancetype)start {
    
    KKBackgroundTask *task = [[KKBackgroundTask alloc] init];
    task.taskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        
        UIBackgroundTaskIdentifier taskID = task.taskID;
        task.taskID = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:taskID];
        
    }];
    return task;
}

- (void)end {
    
    UIBackgroundTaskIdentifier taskID = self.taskID;
    self.taskID = UIBackgroundTaskInvalid;
    [[UIApplication sharedApplication] endBackgroundTask:taskID];
}

@end
