#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 全局通知生命周期监听销毁者
// 开关状态变更回调 helper 类
@interface AntiRevokeToggleHelper : NSObject
@property (nonatomic, weak) UISwitch *toggleSwitch;
@end
@implementation AntiRevokeToggleHelper
- (void)switchToggled:(UISwitch *)sender {
    BOOL isOn = sender.on;
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"AntiRevokeSuite"];
    [d setBool:isOn forKey:kAntiRevokeEnabledKey];
    [d synchronize];
    NSLog(@"[AntiRevoke] 开关状态已更新: %@", isOn ? @"开启" : @"关闭");
}
@end

static id launchObserver = nil;

// 设置开关持久化 Key
static NSString *const kAntiRevokeEnabledKey = @"AntiRevoke_Enabled";

#pragma mark - 0. 设置页面开关 UI

static void injectSettingsToggle() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class settingsVCClass = NSClassFromString(@"WKMeVC");
        if (!settingsVCClass) {
            // 备用：尝试其他设置页类名
            settingsVCClass = NSClassFromString(@"WKSettingsVC");
        }
        if (!settingsVCClass) {
            NSLog(@"[AntiRevoke] 未找到设置页类，跳过开关注入");
            return;
        }
        
        // 在 WKMeVC 的 viewDidLoad 中注入开关
        SEL viewDidLoadSel = @selector(viewDidLoad);
        Method origMethod = class_getInstanceMethod(settingsVCClass, viewDidLoadSel);
        if (!origMethod) return;
        
        IMP origImp = method_getImplementation(origMethod);
        
        IMP newImp = imp_implementationWithBlock(^(id self) {
            // 先执行原 viewDidLoad
            ((void(*)(id, SEL))origImp)(self, viewDidLoadSel);
            
            // 延迟注入开关（等 tableView 加载完毕）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    UITableView *tableView = nil;
                    if ([self isKindOfClass:[UIViewController class]]) {
                        for (UIView *subview in [(UIViewController *)self view].subviews) {
                            if ([subview isKindOfClass:[UIScrollView class]]) {
                                for (UIView *child in subview.subviews) {
                                    if ([child isKindOfClass:[UITableView class]]) {
                                        tableView = (UITableView *)child;
                                        break;
                                    }
                                }
                            }
                            if (tableView) break;
                        }
                    }
                    
                    if (!tableView) {
                        // 尝试通过 KVC 获取
                        tableView = [self valueForKeyPath:@"tableView"];
                    }
                    
                    if (!tableView) {
                        NSLog(@"[AntiRevoke] 未找到设置页 tableView");
                        return;
                    }
                    
                    // 读取当前开关状态
                    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"AntiRevokeSuite"];
                    BOOL enabled = [defaults boolForKey:kAntiRevokeEnabledKey];
                    
                    // 创建开关 Cell
                    UITableViewCell *toggleCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AntiRevokeToggle"];
                    toggleCell.selectionStyle = UITableViewCellSelectionStyleNone;
                    toggleCell.textLabel.text = @"消息防撤回";
                    toggleCell.textLabel.font = [UIFont systemFontOfSize:17];
                    toggleCell.accessoryView = [[UISwitch alloc] init];
                    toggleCell.separatorInset = UIEdgeInsetsZero;
                    
                    UISwitch *toggleSwitch = (UISwitch *)toggleCell.accessoryView;
                    toggleSwitch.on = enabled;
                    toggleSwitch.onTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
                    
                    // 使用 helper 对象接收开关事件
                    AntiRevokeToggleHelper *toggleHelper = [[AntiRevokeToggleHelper alloc] init];
                    toggleHelper.toggleSwitch = toggleSwitch;
                    [toggleSwitch addTarget:toggleHelper action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
                    
                    // 插入到 tableView 第一组末尾
                    @try {
                        NSInteger lastSection = 0;
                        if ([tableView numberOfSections] > 0) {
                            lastSection = 0;
                        }
                        NSInteger rowCount = [tableView numberOfRowsInSection:lastSection];
                        [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:rowCount inSection:lastSection]]
                                          withRowAnimation:UITableViewRowAnimationAutomatic];
                        
                        // 用关联对象持有 cell 和 helper 防止被释放
                        objc_setAssociatedObject(self, "AntiRevokeToggleCell", toggleCell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        objc_setAssociatedObject(self, "AntiRevokeToggleHelper", toggleHelper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    } @catch (NSException *e) {
                        NSLog(@"[AntiRevoke] 插入开关行失败: %@", e.reason);
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[AntiRevoke] 设置页注入安全防御触发: %@", exception.reason);
                }
            });
        });
        
        class_replaceMethod(settingsVCClass, viewDidLoadSel, newImp, method_getTypeEncoding(origMethod));
        NSLog(@"[AntiRevoke] 设置页开关注入成功");
    });
}

// 读取开关状态
static BOOL isAntiRevokeEnabled() {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"AntiRevokeSuite"];
    return [defaults boolForKey:kAntiRevokeEnabledKey];
}

#pragma mark - 1. 动态拦截占位函数

// 阻断消息扩展表批量同步的空实现
static void dummy_extra_imp(id self, SEL _cmd, id extras) {
    NSLog(@"[AntiRevoke] 成功拦截并阻断 message_extra 扩展表的状态覆盖");
}

#pragma mark - 2. 核心拦截与痕迹注入

// 原始数据库更新方法指针缓存
static void (*orig_updateMessageRevoke_clientMsgNo)(id, SEL, id, id) = NULL;

// 核心劫持函数：放行标志位写入，但强行恢复文本并拼接已撤回痕迹
static void hook_updateMessageRevoke_clientMsgNo(id self, SEL _cmd, id revokeStatus, id msgNo) {
    NSLog(@"[AntiRevoke] 捕获到底层数据库撤回修改行为: msgNo = %@", msgNo);
    
    // 先调用原有的数据库更新逻辑，让系统标志位和会话列表正常走完流程，防止状态死锁
    if (orig_updateMessageRevoke_clientMsgNo) {
        orig_updateMessageRevoke_clientMsgNo(self, _cmd, revokeStatus, msgNo);
    }
    
    // 动态获取消息管理器实例以查询内存中的消息模型
    Class managerClass = NSClassFromString(@"WKMessageManager");
    if (!managerClass) return;
    
    id manager = nil;
    if ([managerClass respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
        manager = [managerClass performSelector:NSSelectorFromString(@"sharedInstance")];
    } else if ([managerClass respondsToSelector:NSSelectorFromString(@"sharedManager")]) {
        manager = [managerClass performSelector:NSSelectorFromString(@"sharedManager")];
    }
    
    SEL getMsgSel = NSSelectorFromString(@"getMessageWithClientMsgNo:");
    if (manager && [manager respondsToSelector:getMsgSel]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id messageObj = [manager performSelector:getMsgSel withObject:msgNo];
        #pragma clang diagnostic pop
        
        if (messageObj) {
            @try {
                // 使用安全的 KVC 路径检测和类型断言获取原始文本
                NSString *originalText = [messageObj valueForKeyPath:@"content.text"];
                
                if (originalText && [originalText isKindOfClass:[NSString class]]) {
                    // 检查是否已经加过痕迹，防止重复拼接
                    if (![originalText containsString:@"(对方尝试撤回)"]) {
                        NSString *newText = [originalText stringByAppendingString:@" \n\u26A0\uFE0F (对方尝试撤回)"];
                        
                        // 使用安全键值路径写回，让 UI 下次重绘时自动刷新
                        [messageObj setValue:newText forKeyPath:@"content.text"];
                        
                        // 强制将消息的 revoke 状态在内存中逆转回 0（未撤回状态），欺骗 UI 渲染引擎
                        if (class_getProperty([messageObj class], "revoke") || class_getInstanceVariable([messageObj class], "_revoke")) {
                            [messageObj setValue:@(0) forKey:@"revoke"];
                        }
                        
                        NSLog(@"[AntiRevoke] 痕迹注入成功！已将撤回气泡还原为原始文本内容");
                    }
                }
            } @catch (NSException *exception) {
                NSLog(@"[AntiRevoke] KVC 安全防御触发，跳过痕迹拼接: %@", exception.reason);
            }
        }
    }
}

#pragma mark - 3. 生产级安全 Swizzle 引擎

static void safeSwizzleAndSave(NSString *className, NSString *selectorName, IMP newImp, IMP *origImpCache, const char *types) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        NSLog(@"[AntiRevoke] 运行时未发现类 %@", className);
        return;
    }
    
    SEL targetSelector = NSSelectorFromString(selectorName);
    Method originalMethod = class_getInstanceMethod(targetClass, targetSelector);
    if (!originalMethod) {
        NSLog(@"[AntiRevoke] 运行时未发现方法 [%@ %@]", className, selectorName);
        return;
    }
    
    // 动态提取并严格校验原方法返回值类型，防止寄存器栈错位
    char *returnType = method_copyReturnType(originalMethod);
    if (returnType != NULL) {
        if (strcmp(returnType, @encode(void)) != 0) {
            NSLog(@"[AntiRevoke] 拒绝劫持: %@.%@ 的返回值非 Void！", className, selectorName);
            free(returnType);
            return;
        }
        free(returnType);
    }
    
    if (origImpCache != NULL) {
        *origImpCache = method_getImplementation(originalMethod);
    }
    
    class_replaceMethod(targetClass, targetSelector, newImp, types);
    NSLog(@"[AntiRevoke] 动态方法绑定成功: [%@ %@]", className, selectorName);
}

#pragma mark - 4. 运行时加载与生命周期绑定

static void performDynamicAntiRevoke() {
    static BOOL hasInjected = NO;
    if (hasInjected) return;
    
    if (NSClassFromString(@"WKSystemMessageHandler") || NSClassFromString(@"WKMessageDB")) {
        NSLog(@"[AntiRevoke] 开始动态加载防撤回痕迹全套模块...");
        
        // 核心劫持点：在底层主数据库准备将消息标记为撤回时实施拦截并注入痕迹
        safeSwizzleAndSave(@"WKMessageDB", @"updateMessageRevoke:clientMsgNo:", (IMP)hook_updateMessageRevoke_clientMsgNo, (IMP *)&orig_updateMessageRevoke_clientMsgNo, "v@:@@");
        
        // 传入合法的 dummy_extra_imp 彻底斩断扩展表对历史状态的强行覆盖
        safeSwizzleAndSave(@"WKMessageExtraDB", @"addOrUpdateMessageRevokeExtras:", (IMP)dummy_extra_imp, NULL, "v@:@");
        
        hasInjected = YES;
        
        // 注入设置页开关
        injectSettingsToggle();
    }
}

#pragma mark - 5. 构造初始化入口

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
