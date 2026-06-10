//
//  UUUKeychainHook.m
//  UUUTalk 多开 Keychain Hook
//
//  功能：Hook Security.framework 的 SecItem 系列函数
//        实现多开实例间 Keychain 数据隔离
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "fishhook.h"
#import <dlfcn.h>

#pragma mark - 原函数指针

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef query);

#pragma mark - 多开标识

static NSString *kMultiInstanceSuffix = nil;

__attribute__((constructor))
static void initMultiInstanceSuffix() {
    NSString *suffix = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UUUInstanceSuffix"];
    if (suffix.length > 0) {
        kMultiInstanceSuffix = [suffix copy];
    } else {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSArray *parts = [bundleId componentsSeparatedByString:@"."];
        if (parts.count > 0) {
            NSString *last = parts.lastObject;
            if (last.length == 1) {
                kMultiInstanceSuffix = [last copy];
            }
        }
    }

    if (!kMultiInstanceSuffix) {
        kMultiInstanceSuffix = @"default";
    }

    NSLog(@"[UUUKeychainHook] 多开实例后缀: %@", kMultiInstanceSuffix);
}

#pragma mark - Keychain 查询字典处理

static NSMutableDictionary *isolateQueryDict(CFDictionaryRef query) {
    NSMutableDictionary *dict = [(__bridge NSDictionary *)query mutableCopy];
    if (!dict) return nil;

    // 获取当前的 account/service/generic 值
    id accountVal = CFDictionaryGetValue(query, kSecAttrAccount);
    id serviceVal = CFDictionaryGetValue(query, kSecAttrService);
    id genericVal = CFDictionaryGetValue(query, kSecAttrGeneric);

    // account 追加后缀
    if (accountVal && [accountVal isKindOfClass:[NSString class]]) {
        NSString *account = (NSString *)accountVal;
        if (account.length > 0) {
            dict[(__bridge id)kSecAttrAccount] = [NSString stringWithFormat:@"%@#%@", account, kMultiInstanceSuffix];
        }
    }

    // service 追加后缀
    if (serviceVal && [serviceVal isKindOfClass:[NSString class]]) {
        NSString *service = (NSString *)serviceVal;
        if (service.length > 0) {
            dict[(__bridge id)kSecAttrService] = [NSString stringWithFormat:@"%@#%@", service, kMultiInstanceSuffix];
        }
    }

    // generic 追加后缀（可能是 NSString 或 NSData）
    if (genericVal) {
        NSString *genericStr = nil;
        if ([genericVal isKindOfClass:[NSString class]]) {
            genericStr = (NSString *)genericVal;
        } else if ([genericVal isKindOfClass:[NSData class]]) {
            genericStr = [[NSString alloc] initWithData:(NSData *)genericVal encoding:NSUTF8StringEncoding];
        }
        if (genericStr.length > 0) {
            NSString *newGeneric = [NSString stringWithFormat:@"%@#%@", genericStr, kMultiInstanceSuffix];
            dict[(__bridge id)kSecAttrGeneric] = [newGeneric dataUsingEncoding:NSUTF8StringEncoding];
        }
    }

    return dict;
}

#pragma mark - Hook 实现

static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *isolatedDict = isolateQueryDict(attributes);
    if (!isolatedDict) {
        return orig_SecItemAdd(attributes, result);
    }

    NSLog(@"[UUUKeychainHook] SecItemAdd - account: %@ -> %@",
          CFDictionaryGetValue(attributes, kSecAttrAccount),
          isolatedDict[(__bridge id)kSecAttrAccount]);

    return orig_SecItemAdd((__bridge CFDictionaryRef)isolatedDict, result);
}

static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *isolatedQuery = isolateQueryDict(query);
    if (!isolatedQuery) {
        return orig_SecItemUpdate(query, attributesToUpdate);
    }

    NSLog(@"[UUUKeychainHook] SecItemUpdate - account: %@ -> %@",
          CFDictionaryGetValue(query, kSecAttrAccount),
          isolatedQuery[(__bridge id)kSecAttrAccount]);

    return orig_SecItemUpdate((__bridge CFDictionaryRef)isolatedQuery, attributesToUpdate);
}

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *isolatedQuery = isolateQueryDict(query);
    if (!isolatedQuery) {
        return orig_SecItemCopyMatching(query, result);
    }

    NSLog(@"[UUUKeychainHook] SecItemCopyMatching - account: %@ -> %@",
          CFDictionaryGetValue(query, kSecAttrAccount),
          isolatedQuery[(__bridge id)kSecAttrAccount]);

    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)isolatedQuery, result);

    if (status == errSecItemNotFound) {
        NSLog(@"[UUUKeychainHook] 带后缀查询失败，尝试原始查询...");
        status = orig_SecItemCopyMatching(query, result);
    }

    return status;
}

static OSStatus hook_SecItemDelete(CFDictionaryRef query) {
    NSMutableDictionary *isolatedQuery = isolateQueryDict(query);
    if (!isolatedQuery) {
        return orig_SecItemDelete(query);
    }

    NSLog(@"[UUUKeychainHook] SecItemDelete - account: %@ -> %@",
          CFDictionaryGetValue(query, kSecAttrAccount),
          isolatedQuery[(__bridge id)kSecAttrAccount]);

    return orig_SecItemDelete((__bridge CFDictionaryRef)isolatedQuery);
}

#pragma mark - 初始化 Hook

__attribute__((constructor))
static void initUUUKeychainHook() {
    NSLog(@"[UUUKeychainHook] 开始初始化...");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        struct rebinding rebindings[] = {
            {"SecItemAdd", (void *)hook_SecItemAdd, (void **)&orig_SecItemAdd},
            {"SecItemUpdate", (void *)hook_SecItemUpdate, (void **)&orig_SecItemUpdate},
            {"SecItemCopyMatching", (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
            {"SecItemDelete", (void *)hook_SecItemDelete, (void **)&orig_SecItemDelete}
        };

        int result = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));

        if (result == 0) {
            NSLog(@"[UUUKeychainHook] Hook 成功！实例后缀: %@", kMultiInstanceSuffix);
        } else {
            NSLog(@"[UUUKeychainHook] Hook 失败，错误码: %d", result);
        }
    });
}
