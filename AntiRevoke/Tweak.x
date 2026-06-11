#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static id launchObserver = nil;

#pragma mark - 1. 占位与缓存指针

// 阻断消息扩展表离线同步的空实现
static void dummy_extra_imp(id self, SEL _cmd, id extras) {
    NSLog(@"[AntiRevoke] 已阻断 message_extra 离线同步覆盖");
}

// 缓存原函数指针
static void (*orig_updateMessageRevoke)(id, SEL, id, id) = NULL;
static id (*orig_WKMessage_content)(id, SEL) = NULL;

#pragma mark - 2. 核心拦截：捕获指令并记入黑名单（不调原函数）

static void hook_updateMessageRevoke(id self, SEL _cmd, id revokeStatus, id msgNo) {
    NSLog(@"[AntiRevoke] 捕获到底层撤回修改: msgNo = %@", msgNo);
    
    if (msgNo) {
        // 1. 记录到本地持久化黑名单
        NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *dict = [[def objectForKey:@"UUU_AntiRevoke_List"] mutableCopy] ?: [NSMutableDictionary dictionary];
        dict[[msgNo description]] = @(YES);
        [def setObject:dict forKey:@"UUU_AntiRevoke_List"];
        [def synchronize];
        
        // 2. 动态热修补当前内存中的消息
        Class managerClass = NSClassFromString(@"WKMessageManager");
        if (managerClass) {
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
                        id contentObj = [messageObj valueForKey:@"content"];
                        NSString *textVal = nil;
                        NSString *keyToUpdate = nil;
                        if ([contentObj respondsToSelector:NSSelectorFromString(@"text")]) {
                            textVal = [contentObj valueForKey:@"text"];
                            keyToUpdate = @"text";
                        } else if ([contentObj respondsToSelector:NSSelectorFromString(@"content")]) {
                            textVal = [contentObj valueForKey:@"content"];
                            keyToUpdate = @"content";
                        }
                        
                        if (textVal && [textVal isKindOfClass:[NSString class]] && ![textVal containsString:@"\u26A0\uFE0F (\u5BF9\u65B9\u5C1D\u8BD5\u64A4\u56DE)"]) {
                            NSString *newText = [textVal stringByAppendingString:@" \n\u26A0\uFE0F (\u5BF9\u65B9\u5C1D\u8BD5\u64A4\u56DE)"];
                            [contentObj setValue:newText forKey:keyToUpdate];
                            
                            if (class_getProperty([messageObj class], "revoke") || class_getInstanceVariable([messageObj class], "_revoke")) {
                                [messageObj setValue:@(0) forKey:@"revoke"];
                            }
                        }
                    } @catch (NSException *e) {}
                }
            }
        }
    }
    
    // 绝对不调用原函数！数据库 revoke 永远为 0
}

#pragma mark - 3. 核心拦截：冷启动/重进页面的动态加料

static id hook_WKMessage_content(id self, SEL _cmd) {
    id contentObj = orig_WKMessage_content(self, _cmd);
    
    if (contentObj) {
        @try {
            NSString *msgNo = [self valueForKey:@"clientMsgNo"];
            if (msgNo) {
                NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"UUU_AntiRevoke_List"];
                if (dict && [dict objectForKey:[msgNo description]]) {
                    NSString *textVal = nil;
                    NSString *keyToUpdate = nil;
                    if ([contentObj respondsToSelector:NSSelectorFromString(@"text")]) {
                        textVal = [contentObj valueForKey:@"text"];
                        keyToUpdate = @"text";
                    } else if ([contentObj respondsToSelector:NSSelectorFromString(@"content")]) {
                        textVal = [contentObj valueForKey:@"content"];
                        keyToUpdate = @"content";
                    }
                    
                    if (textVal && [textVal isKindOfClass:[NSString class]] && ![textVal containsString:@"\u26A0\uFE0F (\u5BF9\u65B9\u5C1D\u8BD5\u64A4\u56DE)"]) {
                        NSString *newText = [textVal stringByAppendingString:@" \n\u26A0\uFE0F (\u5BF9\u65B9\u5C1D\u8BD5\u64A4\u56DE)"];
                        [contentObj setValue:newText forKey:keyToUpdate];
                    }
                }
            }
        } @catch (NSException *e) {}
    }
    
    return contentObj;
}

#pragma mark - 4. 安全 Swizzle 引擎

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
    
    // 动态校验返回值类型首字符
    char *returnType = method_copyReturnType(originalMethod);
    if (returnType != NULL) {
        if (returnType[0] != types[0]) {
            NSLog(@"[AntiRevoke] 拒绝劫持: %@.%@ 返回值类型不匹配！", className, selectorName);
            free(returnType);
            return;
        }
        free(returnType);
    }
    
    if (origImpCache != NULL) {
        *origImpCache = method_getImplementation(originalMethod);
    }
    
    class_replaceMethod(targetClass, targetSelector, newImp, types);
    NSLog(@"[AntiRevoke] 核心防御注入成功: [%@ %@]", className, selectorName);
}

#pragma mark - 5. 设置页开关 UI

@interface AntiRevokeToggleHelper : NSObject
@property (nonatomic, weak) UISwitch *toggleSwitch;
@end
@implementation AntiRevokeToggleHelper
- (void)switchToggled:(UISwitch *)sender {
    BOOL isOn = sender.on;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:isOn forKey:@"AntiRevoke_Enabled"];
    [d synchronize];
    NSLog(@"[AntiRevoke] 开关状态: %@", isOn ? @"开启" : @"关闭");
}
@end

static void injectSettingsToggle() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class settingsVCClass = NSClassFromString(@"WKMeVC");
        if (!settingsVCClass) {
            settingsVCClass = NSClassFromString(@"WKSettingsVC");
        }
        if (!settingsVCClass) {
            NSLog(@"[AntiRevoke] 未找到设置页类");
            return;
        }
        
        SEL viewDidLoadSel = @selector(viewDidLoad);
        Method origMethod = class_getInstanceMethod(settingsVCClass, viewDidLoadSel);
        if (!origMethod) return;
        
        IMP origImp = method_getImplementation(origMethod);
        
        IMP newImp = imp_implementationWithBlock(^(id self) {
            ((void(*)(id, SEL))origImp)(self, viewDidLoadSel);
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    UITableView *tableView = nil;
                    
                    // 方式1: KVC 尝试常见属性名
                    NSArray *kvcKeys = @[@"tableView", @"_tableView", @"table"];
                    for (NSString *key in kvcKeys) {
                        @try {
                            id val = [self valueForKey:key];
                            if ([val isKindOfClass:[UITableView class]]) {
                                tableView = val;
                                break;
                            }
                        } @catch (NSException *e) {}
                    }
                    
                    // 方式2: 视图层级遍历
                    if (!tableView && [self isKindOfClass:[UIViewController class]]) {
                        UIViewController *vc = (UIViewController *)self;
                        NSArray *subviews = vc.view.subviews;
                        for (UIView *subview in subviews) {
                            if ([subview isKindOfClass:[UITableView class]]) {
                                tableView = (UITableView *)subview;
                                break;
                            }
                            // UIScrollView 子视图
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
                        NSLog(@"[AntiRevoke] 未找到设置页 tableView");
                        return;
                    }
                    
                    // 读取开关状态
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    BOOL enabled = [defaults boolForKey:@"AntiRevoke_Enabled"];
                    
                    // 创建开关 Cell
                    UITableViewCell *toggleCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AntiRevokeToggle"];
                    toggleCell.selectionStyle = UITableViewCellSelectionStyleNone;
                    toggleCell.textLabel.text = @"消息防撤回";
                    toggleCell.textLabel.font = [UIFont systemFontOfSize:17];
                    toggleCell.detailTextLabel.text = enabled ? @"已开启" : @"已关闭";
                    toggleCell.detailTextLabel.textColor = enabled ? [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0] : [UIColor grayColor];
                    toggleCell.accessoryView = [[UISwitch alloc] init];
                    toggleCell.separatorInset = UIEdgeInsetsZero;
                    
                    UISwitch *toggleSwitch = (UISwitch *)toggleCell.accessoryView;
                    toggleSwitch.on = enabled;
                    toggleSwitch.onTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
                    
                    AntiRevokeToggleHelper *toggleHelper = [[AntiRevokeToggleHelper alloc] init];
                    toggleHelper.toggleSwitch = toggleSwitch;
                    [toggleSwitch addTarget:toggleHelper action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
                    
                    // 插入到第一组末尾
                    NSInteger section = 0;
                    NSInteger rowCount = [tableView numberOfRowsInSection:section];
                    [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:rowCount inSection:section]]
                                          withRowAnimation:UITableViewRowAnimationFade];
                    
                    objc_setAssociatedObject(self, "AntiRevokeToggleCell", toggleCell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(self, "AntiRevokeToggleHelper", toggleHelper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    
                    NSLog(@"[AntiRevoke] 设置页开关注入成功");
                } @catch (NSException *exception) {
                    NSLog(@"[AntiRevoke] 设置页注入异常: %@", exception.reason);
                }
            });
        });
        
        class_replaceMethod(settingsVCClass, viewDidLoadSel, newImp, method_getTypeEncoding(origMethod));
    });
}

#pragma mark - 6. 动态加载与生命周期绑定

static void performDynamicAntiRevoke() {
    static BOOL hasInjected = NO;
    if (hasInjected) return;
    
    if (NSClassFromString(@"WKMessageDB") || NSClassFromString(@"WKMessage")) {
        NSLog(@"[AntiRevoke] 开始挂载防撤回+显痕迹双擎核心...");
        
        // 1. 拦截底层数据库写入，阻断 revoke 标记，记录黑名单
        safeSwizzleAndSave(@"WKMessageDB", @"updateMessageRevoke:clientMsgNo:", (IMP)hook_updateMessageRevoke, (IMP *)&orig_updateMessageRevoke, "v@:@@");
        
        // 2. 拦截消息模型的 content 读取，动态为黑名单消息加尾巴
        safeSwizzleAndSave(@"WKMessage", @"content", (IMP)hook_WKMessage_content, (IMP *)&orig_WKMessage_content, "@@:");
        
        // 3. 彻底阻断历史漫游拉取时的扩展表状态覆盖
        safeSwizzleAndSave(@"WKMessageExtraDB", @"addOrUpdateMessageRevokeExtras:", (IMP)dummy_extra_imp, NULL, "v@:@");
        
        hasInjected = YES;
        
        // 注入设置页开关
        injectSettingsToggle();
    }
}

#pragma mark - 7. 构造初始化入口

%ctor {
    if (NSClassFromString(@"WKMessageDB")) {
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
