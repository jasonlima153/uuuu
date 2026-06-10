#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

static UIBackgroundTaskIdentifier bgTask;

%ctor {
    bgTask = UIBackgroundTaskInvalid;
}

#pragma mark - 1. UserDefaults 沙盒硬隔离 (ObjC 层)

%hook NSUserDefaults

- (instancetype)initWithSuiteName:(NSString *)suitename {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleId && ([bundleId hasSuffix:@".a"] || [bundleId hasSuffix:@".b"] || [bundleId hasSuffix:@".c"] || [bundleId hasSuffix:@".1"] || [bundleId hasSuffix:@".2"])) {
        NSString *newSuite = [NSString stringWithFormat:@"%@_isolated", bundleId];
        return %orig(newSuite);
    }
    return %orig(suitename);
}

+ (NSUserDefaults *)standardUserDefaults {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleId && ([bundleId hasSuffix:@".a"] || [bundleId hasSuffix:@".b"] || [bundleId hasSuffix:@".c"] || [bundleId hasSuffix:@".1"] || [bundleId hasSuffix:@".2"])) {
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

#pragma mark - 3. 后台流氓保活 + 拦截主动断网

%hook UIApplication

- (void)applicationDidEnterBackground:(UIApplication *)application {
    %orig;
    
    bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
        NSLog(@"[UUUTalk_Hook] 30秒大限已到，App 挂起");
    }];
    
    // 开启 AudioSession Playback 模式，欺骗系统认为我们在后台播放音频
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    
    NSLog(@"[UUUTalk_Hook] 申请后台续命成功，AudioSession 已激活");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    %orig;
    if (bgTask != UIBackgroundTaskInvalid) {
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

%end

#pragma mark - 4. 拦截网络库监听后台通知，防止主动断网

%hook NSNotificationCenter

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSNotificationName)aName object:(id)anObject {
    if ([aName isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        NSString *className = NSStringFromClass([observer class]);
        if ([className containsString:@"Socket"] || 
            [className containsString:@"LiveKit"] || 
            [className containsString:@"WebRTC"] || 
            [className containsString:@"Network"] ||
            [className containsString:@"WebSocket"] ||
            [className containsString:@"IOClient"] ||
            [className containsString:@"Connection"]) {
            
            NSLog(@"[UUUTalk_Hook] 拦截 %@ 监听后台通知，防止主动断网", className);
            return;
        }
    }
    %orig;
}

%end
