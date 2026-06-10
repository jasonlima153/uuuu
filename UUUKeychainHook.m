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

// 原始 SecItemAdd
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);

// 原始 SecItemUpdate
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);

// 原始 SecItemCopyMatching
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);

// 原始 SecItemDelete
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef query);

#pragma mark - 多开标识

// 每个多开实例使用不同的后缀，例如：.a, .b, .c
static NSString *kMultiInstanceSuffix = nil;

// 初始化多开后缀（在 +load 或 AppDelegate 中调用）
__attribute__((constructor))
static void initMultiInstanceSuffix() {
    // 方式1：从 Info.plist 读取
    NSString *suffix = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UUUInstanceSuffix"];
    if (suffix.length > 0) {
        kMultiInstanceSuffix = [suffix copy];
    } else {
        // 方式2：从 Bundle ID 提取后缀
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSArray *parts = [bundleId componentsSeparatedByString:@"."];
        if (parts.count > 0) {
            NSString *last = parts.lastObject;
            if (last.length == 1) { // 如 com.birch.UUUTalk.a
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

// 为 Keychain 查询添加多开隔离标识
static NSMutableDictionary *isolateQueryDict(CFDictionaryRef query) {
    NSMutableDictionary *dict = [(__bridge NSDictionary *)query mutableCopy];
    if (!dict) return nil;
    
    // 获取当前的 account/service 值
    NSString *account = dict[(__bridge id)kSecAttrAccount];
    NSString *service = dict[(__bridge id)kSecAttrService];
    NSString *generic = dict[(__bridge id)kSecAttrGeneric];
    
    // 在 account 后追加实例后缀
    if (account && account.length > 0) {
        dict[(__bridge id)kSecAttrAccount] = [NSString stringWithFormat:@"%@#%@", account, kMultiInstanceSuffix];
    }
    
    // 在 service 后追加实例后缀
    if (service && service.length > 0) {
        dict[(__bridge id)kSecAttrService] = [NSString stringWithFormat:@"%@#%@", service, kMultiInstanceSuffix];
    }
    
    // 在 generic 后追加实例后缀（如果存在）
    if (generic) {
        NSString *genericStr = [[NSString alloc] initWithData:generic encoding:NSUTF8StringEncoding];
        if (genericStr.length > 0) {
            NSString *newGeneric = [NSString stringWithFormat:@"%@#%@", genericStr, kMultiInstanceSuffix];
            dict[(__bridge id)kSecAttrGeneric] = [newGeneric dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
    
    return dict;
}

// 从隔离后的值还原原始值（用于返回给调用方）
static NSString *restoreOriginalKey(NSString *isolatedKey) {
    if (!isolatedKey) return nil;
    NSRange range = [isolatedKey rangeOfString:@"#" options:NSBackwardsSearch];
    if (range.location != NSNotFound) {
        return [isolatedKey substringToIndex:range.location];
    }
    return isolatedKey;
}

#pragma mark - Hook 实现

// Hook: SecItemAdd
static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *isolatedDict = isolateQueryDict(attributes);
    if (!isolatedDict) {
        return orig_SecItemAdd(attributes, result);
    }
    
    NSLog(@"[UUUKeychainHook] SecItemAdd - account: %@ -> %@",
          attributes[(__bridge id)kSecAttrAccount],
          isolatedDict[(__bridge id)kSecAttrAccount]);
    
    return orig_SecItemAdd((__bridge CFDictionaryRef)isolatedDict, result);
}

// Hook: SecItemUpdate
static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *isolatedQuery = isolateQueryDict(query);
    if (!isolatedQuery) {
        return orig_SecItemUpdate(query, attributesToUpdate);
    }
    
    NSLog(@"[UUUKeychainHook] SecItemUpdate - account: %@ -> %@",
          query[(__bridge id)kSecAttrAccount],
          isolatedQuery[(__bridge id)kSecAttrAccount]);
    
    return orig_SecItemUpdate((__bridge CFDictionaryRef)isolatedQuery, attributesToUpdate);
}

// Hook: SecItemCopyMatching
static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *isolatedQuery = isolateQueryDict(query);
    if (!isolatedQuery) {
        return orig_SecItemCopyMatching(query, result);
    }
    
    NSLog(@"[UUUKeychainHook] SecItemCopyMatching - account: %@ -> %@",
          query[(__bridge id)kSecAttrAccount],
          isolatedQuery[(__bridge id)kSecAttrAccount]);
    
    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)isolatedQuery, result);
    
    // 如果查询失败，尝试不带后缀查询（兼容旧数据）
    if (status == errSecItemNotFound) {
        NSLog(@"[UUUKeychainHook] 带后缀查询失败，尝试原始查询...");
        status = orig_SecItemCopyMatching(query, result);
    }
    
    return status;
}

// Hook: SecItemDelete
static OSStatus hook_SecItemDelete(CFDictionaryRef query) {
    NSMutableDictionary *isolatedQuery = isolateQueryDict(query);
    if (!isolatedQuery) {
        return orig_SecItemDelete(query);
    }
    
    NSLog(@"[UUUKeychainHook] SecItemDelete - account: %@ -> %@",
          query[(__bridge id)kSecAttrAccount],
          isolatedQuery[(__bridge id)kSecAttrAccount]);
    
    return orig_SecItemDelete((__bridge CFDictionaryRef)isolatedQuery);
}

#pragma mark - 初始化 Hook

__attribute__((constructor))
static void initUUUKeychainHook() {
    NSLog(@"[UUUKeychainHook] 开始初始化...");
    
    // 等待多开后缀初始化完成
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
