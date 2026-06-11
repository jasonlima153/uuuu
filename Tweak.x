#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

// 引入干净的音频二进制头文件
#import "silent_mp3.h"

static UIBackgroundTaskIdentifier bgTask = 0xFFFFFFFF;
static AVAudioPlayer *audioPlayer = nil;
static dispatch_source_t heartbeatTimer = nil;
static NSString *mp3SandboxPath = nil;

static id observerDidEnterBackground = nil;
static id observerWillEnterForeground = nil;

#pragma mark - 1. 沙盒音频释放

static void extractSilentMp3ToSandbox() {
    NSString *tmpDir = NSTemporaryDirectory();
    mp3SandboxPath = [tmpDir stringByAppendingPathComponent:@"uuu_live_silent.mp3"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:mp3SandboxPath]) {
        NSData *mp3Data = [NSData dataWithBytes:silent_mp3_data length:silent_mp3_len];
        [mp3Data writeToFile:mp3SandboxPath atomically:YES];
        NSLog(@"[UUUTalk_Hook] 静音 MP3 沙盒释放成功");
    }
}

#pragma mark - 2. 音频保活与安全重置

static void startAudioPlay() {
    if (audioPlayer && audioPlayer.isPlaying) return;
    extractSilentMp3ToSandbox();
    
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    [session setActive:YES error:&error];
    
    NSURL *url = [NSURL fileURLWithPath:mp3SandboxPath];
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    
    if (error || !audioPlayer) {
        NSLog(@"[UUUTalk_Hook] AVAudioPlayer 启动失败: %@", error);
        return;
    }
    
    audioPlayer.numberOfLoops = -1;
    
    // 降低 CPU 解码功耗
    audioPlayer.enableRate = YES;
    audioPlayer.rate = 0.5;
    audioPlayer.volume = 0.01;
    
    [audioPlayer prepareToPlay];
    [audioPlayer play];
    NSLog(@"[UUUTalk_Hook] 后台音频保活已启动 (低功耗模式)");
}

static void stopAudioPlay() {
    if (audioPlayer) {
        [audioPlayer stop];
        audioPlayer = nil;
    }
}

#pragma mark - 3. GCD 辅助心跳（保持 FIMKit 长连接存活）

static void startBackgroundHeartbeat() {
    if (heartbeatTimer) return;
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    // 3分钟心跳 + 15秒系统误差对齐，大幅降低基带天线功耗
    dispatch_source_set_timer(heartbeatTimer, dispatch_walltime(NULL, 0), 180.0 * NSEC_PER_SEC, 15.0 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(heartbeatTimer, ^{
        Class managerClass = NSClassFromString(@"WKConnectionManager");
        if (managerClass) {
            id manager = nil;
            if ([managerClass respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
                manager = [managerClass performSelector:NSSelectorFromString(@"sharedInstance")];
            } else if ([managerClass respondsToSelector:NSSelectorFromString(@"sharedManager")]) {
                manager = [managerClass performSelector:NSSelectorFromString(@"sharedManager")];
            }
            
            if (manager) {
                if ([manager respondsToSelector:NSSelectorFromString(@"checkAndSendHeartbeat")]) {
                    [manager performSelector:NSSelectorFromString(@"checkAndSendHeartbeat")];
                } else if ([manager respondsToSelector:NSSelectorFromString(@"sendPing")]) {
                    [manager performSelector:NSSelectorFromString(@"sendPing")];
                }
            }
        }
    });
    dispatch_resume(heartbeatTimer);
}

static void stopBackgroundHeartbeat() {
    if (heartbeatTimer) {
        dispatch_source_cancel(heartbeatTimer);
        heartbeatTimer = nil;
    }
}

#pragma mark - 4. FIMKit WKConnectionManager 断网拦截

%group WKNetworkHook

%hook WKConnectionManager

- (void)disconnect {
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        NSLog(@"[UUUTalk_Hook] 拦截 FIMKit 后台 disconnect");
        return;
    }
    %orig;
}

- (void)forceDisconnect {
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        NSLog(@"[UUUTalk_Hook] 拦截 FIMKit 后台 forceDisconnect");
        return;
    }
    %orig;
}

%end

%end

#pragma mark - 5. NSUserDefaults 沙盒隔离

%hook NSUserDefaults

- (instancetype)initWithSuiteName:(NSString *)suitename {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleId && ([bundleId hasSuffix:@".a"] || [bundleId hasSuffix:@".b"] || [bundleId hasSuffix:@".c"] || [bundleId hasSuffix:@".1"] || [bundleId hasSuffix:@".2"])) {
        NSString *isolatedSuite = [NSString stringWithFormat:@"%@_isolated", bundleId];
        return %orig(isolatedSuite);
    }
    return %orig(suitename);
}

%end

#pragma mark - 6. 拦截网络库监听后台通知

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
            
            NSLog(@"[UUUTalk_Hook] 拦截 %@ 监听后台通知", className);
            return;
        }
    }
    %orig;
}

%end

#pragma mark - 7. 构造初始化

%ctor {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    observerDidEnterBackground = [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                 object:nil 
                                                  queue:nil
                                             usingBlock:^(NSNotification *note) {
        startAudioPlay();
        startBackgroundHeartbeat();
        
        bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = 0xFFFFFFFF;
        }];
    }];
    
    observerWillEnterForeground = [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                                                  object:nil 
                                                   queue:nil
                                              usingBlock:^(NSNotification *note) {
        stopAudioPlay();
        stopBackgroundHeartbeat();
        if (bgTask != 0xFFFFFFFF) {
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = 0xFFFFFFFF;
        }
    }];
    
    extractSilentMp3ToSandbox();
    
    // 动态检测 FIMKit 是否存在，存在则初始化 WKNetworkHook 组
    if (NSClassFromString(@"WKConnectionManager")) {
        %init(WKNetworkHook);
    }
    
    %init;
}
