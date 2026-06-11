#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static id launchObserver = nil;

#pragma mark - 1. 本地黑名单持久化

static void addMsgToBlacklist(NSString *msgNo) {
    if (!msgNo || msgNo.length == 0) return;
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [[def objectForKey:@"UUU_AntiRevoke_List"] mutableCopy] ?: [NSMutableDictionary dictionary];
    dict[msgNo] = @(YES);
    [def setObject:dict forKey:@"UUU_AntiRevoke_List"];
}

static BOOL isMsgInBlacklist(NSString *msgNo) {
    if (!msgNo || msgNo.length == 0) return NO;
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"UUU_AntiRevoke_List"];
    return [dict[msgNo] boolValue];
}

#pragma mark - 2. 核心 Logos Hook 安全隔离组

%group AntiRevokeCore

// 关卡一：拦截底层数据库标记
%hook WKMessageDB
- (void)updateMessageRevoke:(id)revoke clientMsgNo:(NSString *)msgNo {
    NSLog(@"[AntiRevoke] 拦截到数据库撤回标记 msgNo: %@", msgNo);
    if (msgNo) {
        addMsgToBlacklist(msgNo);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WKNotificationMessageUpdate" object:nil];
        });
    }
}
%end

%hook WKMessageExtraDB
- (void)addOrUpdateMessageRevokeExtras:(id)extras {
    NSLog(@"[AntiRevoke] 已阻断 message_extra 离线扩展同步");
}
%end

// 关卡二：模型层降维打击
%hook WKMessage

- (NSString *)content {
    NSString *origContent = %orig;
    
    @try {
        NSString *msgNo = [self valueForKey:@"clientMsgNo"];
        if (isMsgInBlacklist(msgNo)) {
            if ([origContent isKindOfClass:[NSString class]] && ![origContent containsString:@"\u26A0\uFE0F (\u5BF9\u65B9\u5C1D\u8BD5\u64A4\u56DE)"]) {
                return [origContent stringByAppendingString:@" \n\u26A0\uFE0F (\u5BF9\u65B9\u5C1D\u8BD5\u64A4\u56DE)"];
            }
        }
    } @catch(NSException *e) {}
    
    return origContent;
}

- (id)remoteExtra {
    id extra = %orig;
    @try {
        NSString *msgNo = [self valueForKey:@"clientMsgNo"];
        if (isMsgInBlacklist(msgNo) && extra) {
            [extra setValue:@(0) forKey:@"revoke"];
        }
    } @catch(NSException *e) {}
    return extra;
}

- (NSInteger)contentType {
    NSInteger type = %orig;
    @try {
        NSString *msgNo = [self valueForKey:@"clientMsgNo"];
        if (isMsgInBlacklist(msgNo) && type == 99) {
            return 1;
        }
    } @catch(NSException *e) {}
    return type;
}

%end

%end

#pragma mark - 3. 动态安全初始化

static void initAntiRevoke() {
    static BOOL injected = NO;
    if (injected) return;
    
    if (NSClassFromString(@"WKMessageDB") && NSClassFromString(@"WKMessage")) {
        NSLog(@"[AntiRevoke] 核心类校验通过，激活 Logos 防撤回引擎...");
        %init(AntiRevokeCore);
        injected = YES;
    }
}

#pragma mark - 4. 构造初始化入口

%ctor {
    if (NSClassFromString(@"WKMessageDB")) {
        initAntiRevoke();
    } else {
        launchObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil 
                                                          queue:nil
                                                     usingBlock:^(NSNotification *note) {
            initAntiRevoke();
            [[NSNotificationCenter defaultCenter] removeObserver:launchObserver];
            launchObserver = nil;
        }];
    }
    %init;
}
