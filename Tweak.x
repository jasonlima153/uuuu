#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>

static UIBackgroundTaskIdentifier bgTask;

%ctor {
    bgTask = UIBackgroundTaskInvalid;
}

#pragma mark - 1. UserDefaults 沙盒硬隔离 (ObjC 层)

%hook NSUserDefaults

- (instancetype)initWithSuiteName:(NSString *)suitename {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleId hasSuffix:@".a"] || [bundleId hasSuffix:@".b"] || [bundleId hasSuffix:@".c"] || [bundleId hasSuffix:@".1"] || [bundleId hasSuffix:@".2"]) {
        NSString *newSuite = [NSString stringWithFormat:@"%@_isolated", bundleId];
        return %orig(newSuite);
    }
    return %orig(suitename);
}

+ (NSUserDefaults *)standardUserDefaults {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleId hasSuffix:@".a"] || [bundleId hasSuffix:@".b"] || [bundleId hasSuffix:@".c"] || [bundleId hasSuffix:@".1"] || [bundleId hasSuffix:@".2"]) {
        return [[NSUserDefaults alloc] initWithSuiteName:bundleId];
    }
    return %orig;
}

%end

#pragma mark - 2. WebSocket 拦截与系统弹窗/发声

static void triggerLocalNotification(NSString *msgContent) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"UUUTalk 新消息";
    content.body = msgContent ? msgContent : @"您有一条新消息";
    content.sound = [UNNotificationSound defaultSound]; 
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:trigger];
    
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
    
    // 【核心破壁发声】无视 AudioSession 抢占，调用底层 C API 播放系统短信音 (1007)
    AudioServicesPlaySystemSound(1007);
}

%hook NSURLSessionWebSocketTask

- (void)receiveMessageWithCompletionHandler:(void (^)(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error))completionHandler {
    
    void (^hookedHandler)(NSURLSessionWebSocketMessage *, NSError *) = ^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (!error && message) {
            NSString *extractText = @"收到新消息";
            
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                extractText = message.string;
            } else if (message.type == NSURLSessionWebSocketMessageTypeData) {
                extractText = [[NSString alloc] initWithData:message.data encoding:NSUTF8StringEncoding];
            }
            
            // 过滤心跳包 (需要根据抓包实际情况修改过滤词，比如 "ping" 或 "heartbeat")
            if (![extractText containsString:@"heartbeat"]) {
                if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
                    triggerLocalNotification(@"您收到了一条新消息，请点击查看");
                }
            }
        }
        
        if (completionHandler) {
            completionHandler(message, error);
        }
    };
    
    %orig(hookedHandler);
}

%end

#pragma mark - 3. 后台续命机制

%hook UIApplication

- (void)applicationDidEnterBackground:(UIApplication *)application {
    %orig;
    
    bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
        NSLog(@"[UUUTalk_Hook] 30秒大限已到，App 挂起");
    }];
    NSLog(@"[UUUTalk_Hook] 申请后台续命成功，30秒内 WebSocket 保持连接");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    %orig;
    if (bgTask != UIBackgroundTaskInvalid) {
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

%end
