#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 1. 屏幕顶部弹窗提示

static void showAntiRevokeToast() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        
        if (@available(iOS 15.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene.delegate conformsToProtocol:@protocol(UIWindowSceneDelegate)]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    keyWindow = windowScene.keyWindow;
                    if (keyWindow) break;
                }
            }
        }
        
        if (!keyWindow) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
            #pragma clang diagnostic pop
        }
        
        if (!keyWindow) return;
        
        UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, keyWindow.bounds.size.width - 40, 40)];
        toast.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.95];
        toast.textColor = [UIColor whiteColor];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.font = [UIFont boldSystemFontOfSize:15];
        toast.layer.cornerRadius = 8;
        toast.clipsToBounds = YES;
        toast.text = @"🚫 成功拦截对方撤回操作";
        
        toast.layer.shadowColor = [UIColor blackColor].CGColor;
        toast.layer.shadowOffset = CGSizeMake(0, 2);
        toast.layer.shadowOpacity = 0.3;
        
        [keyWindow addSubview:toast];
        
        [UIView animateWithDuration:0.5 delay:3.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            toast.alpha = 0;
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    });
}

#pragma mark - 2. 核心拦截引擎

%group UUUTalkAntiRevoke

// 关卡一：斩断 CMD 撤回命令
%hook WKSystemMessageHandler
- (void)handle_messageRevoke_withParameter:(id)param {
    NSLog(@"[AntiRevoke] \u6355\u83B7\u5B9E\u65F6\u64A4\u56DE\u4FE1\u4EE4: %@", param);
    showAntiRevokeToast();
}
%end

// 关卡二：拦截本地代理执行
%hook WKMessageManagerDelegateImp
- (void)revokeLocalMessage:(id)message {
    NSLog(@"[AntiRevoke] \u62E6\u622A\u672C\u5730\u64A4\u56DE\u6267\u884C");
}
%end

// 关卡三：拦截数据库写入
%hook WKMessageDB
- (void)updateMessageRevoke:(id)revoke clientMsgNo:(id)msgNo {
    NSLog(@"[AntiRevoke] \u62E6\u622A\u6570\u636E\u5E93\u64A4\u56DE\u6807\u8BB0");
}
%end

// 关卡四：拦截扩展表离线同步
%hook WKMessageExtraDB
- (void)addOrUpdateMessageRevokeExtras:(id)extras {
    NSLog(@"[AntiRevoke] \u62E6\u622A\u6269\u5C55\u8868\u540C\u6B65");
}
%end

// 关卡五：模型层强制欺骗
%hook WKMessageExtra
- (BOOL)revoke {
    return NO;
}
%end

// 关卡六：屏蔽主页会话列表撤回提示
%hook WKConversationListCell
- (id)revokeTip {
    return nil;
}
%end

%end

#pragma mark - 3. 生命周期绑定

%ctor {
    id obs = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                     object:nil 
                                                      queue:nil
                                                 usingBlock:^(NSNotification *note) {
        [[NSNotificationCenter defaultCenter] removeObserver:obs];
        %init(UUUTalkAntiRevoke);
    }];
}
