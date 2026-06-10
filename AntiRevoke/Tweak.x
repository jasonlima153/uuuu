#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 全局通知生命周期监听销毁者
static id launchObserver = nil;

#pragma mark - 1. 动态拦截通用占位函数

// 针对 Void 返回值方法的通用熔断器（接收单参数）
static void dummy_void_imp(id self, SEL _cmd, id param) {
    NSLog(@"[AntiRevoke] 动态安全拦截器：已熔断单参数方法 [%@]", NSStringFromSelector(_cmd));
}

// 针对 Void 返回值方法的通用熔断器（接收双参数，专门针对数据库更新）
static void dummy_db_imp(id self, SEL _cmd, id arg1, id arg2) {
    NSLog(@"[AntiRevoke] 动态安全拦截器：已熔断双参数数据库更新方法 [%@]", NSStringFromSelector(_cmd));
}

#pragma mark - 2. 生产级返回值安全校验 Swizzle 引擎

static void safeSwizzle(NSString *className, NSString *selectorName, IMP dummyImp, const char *expectedTypes) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        NSLog(@"[AntiRevoke] 安全跳过：未发现类 %@", className);
        return;
    }
    
    SEL targetSelector = NSSelectorFromString(selectorName);
    Method originalMethod = class_getInstanceMethod(targetClass, targetSelector);
    if (!originalMethod) {
        NSLog(@"[AntiRevoke] 安全跳过：类 %@ 中未发现方法 %@", className, selectorName);
        return;
    }
    
    // 动态提取并严格校验原方法返回值类型，防止 ARM64 寄存器栈错位崩溃
    char *returnType = method_copyReturnType(originalMethod);
    if (returnType != NULL) {
        if (strcmp(returnType, @encode(void)) != 0) {
            NSLog(@"[AntiRevoke] 警告：检测到 %@.%@ 的实际返回值类型为 '%s' (非Void)！已自动跳过该方法的 Hook！", className, selectorName, returnType);
            free(returnType);
            return;
        }
        free(returnType);
    }
    
    class_replaceMethod(targetClass, targetSelector, dummyImp, expectedTypes);
    NSLog(@"[AntiRevoke] 核心防御方法劫持成功：[%@ %@]", className, selectorName);
}

#pragma mark - 3. 运行时动态加载与双重验证

static void performDynamicAntiRevoke() {
    static BOOL hasInjected = NO;
    if (hasInjected) return;
    
    if (NSClassFromString(@"WKSystemMessageHandler") || NSClassFromString(@"WKMessageDB")) {
        NSLog(@"[AntiRevoke] 开始执行生产级方法签名与返回值类型双重校验...");
        
        // 1. 熔断最外层 CMD 撤回命令路由 [FAMainModule]
        safeSwizzle(@"WKSystemMessageHandler", @"handle_messageRevoke_withParameter:", (IMP)dummy_void_imp, "v@:@");
        
        // 2. 阻断本地消息变更为撤回提示的刷新回调 [FADataSource]
        safeSwizzle(@"WKMessageManagerDelegateImp", @"revokeLocalMessage:", (IMP)dummy_void_imp, "v@:@");
        
        // 3. 拦截本地数据库主表 (message表) 的撤回更新写入 [FIMKit]
        safeSwizzle(@"WKMessageDB", @"updateMessageRevoke:clientMsgNo:", (IMP)dummy_db_imp, "v@:@@");
        
        // 4. 拦截离线历史同步时扩展表 (message_extra表) 的批量撤回状态更新 [FIMKit]
        safeSwizzle(@"WKMessageExtraDB", @"addOrUpdateMessageRevokeExtras:", (IMP)dummy_void_imp, "v@:@");
        
        hasInjected = YES;
    }
}

#pragma mark - 4. 构造初始化入口

%ctor {
    if (NSClassFromString(@"WKSystemMessageHandler")) {
        performDynamicAntiRevoke();
    } else {
        launchObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil 
                                                          queue:nil
                                                     usingBlock:^(NSNotification *note) {
            performDynamicAntiRevoke();
            [[NSNotificationCenter defaultCenter] removeObserver:launchObserver];
            launchObserver = nil;
        }];
    }
    
    %init;
}
