# UUUTalkFix

UUUTalk 多开修复 Tweak。通过 Hook ObjC Runtime 和 Security.framework C 函数，解决多开场景下的通知无声、Keychain 串号、UserDefaults 覆盖等问题。

## 功能特性

- **UserDefaults 隔离**：Hook `NSUserDefaults`，多开实例使用独立的 SuiteName
- **WebSocket 消息拦截**：Hook `NSURLSessionWebSocketTask`，后台收到消息时触发本地通知 + 系统提示音
- **后台续命**：Hook `UIApplication`，进入后台时申请 `beginBackgroundTask`，延长 WebSocket 连接时间
- **Keychain 隔离**：通过 fishhook Hook `SecItemAdd/Update/CopyMatching/Delete`，为每个多开实例追加独立后缀，防止 APNs Token 被覆盖
- **查询回退**：`SecItemCopyMatching` 带后缀查询失败时，自动回退到原始查询，兼容旧数据

## 工程结构

```
UUUTalkFix/
├── Makefile                # Theos 编译配置
├── Tweak.x                 # Logos 代码 (ObjC Runtime Hook)
├── UUUKeychainHook.m       # Keychain C 函数 Hook (fishhook)
├── fishhook.c              # Facebook fishhook 源码
├── fishhook.h              # Facebook fishhook 头文件
└── .github/workflows/
    └── build.yml           # GitHub Actions CI 自动编译
```

## 本地编译

需要安装 [Theos](https://theos.dev/)：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

编译：

```bash
cd UUUTalkFix
export THEOS=~/theos
make
```

编译产物位于 `.theos/obj/debug/UUUTalkFix.dylib`。

## GitHub Actions 自动编译

本仓库已配置 CI，推送代码后自动在 macOS  runner 上编译 dylib：

1. 将本仓库推送到 GitHub
2. 进入 Actions 页面查看构建进度
3. 构建完成后在 Artifacts 中下载 `UUUTalkFix.dylib`
4. 打 tag 可自动触发 Release，附带 dylib 附件

## 注入与签名

1. 使用 [Sideloadly](https://sideloadly.io/)、[Azule](https://github.com/Al4ise/Azule) 或 `optool` 将 `UUUTalkFix.dylib` 注入到原版 UUUTalk.ipa
2. 修改 `Info.plist` 的 `CFBundleIdentifier`（例如 `com.birch.UUUTalk.a`）
3. 使用个人/企业证书重签名并安装

## 多开实例命名规则

Bundle ID 最后一位作为实例后缀：

- `com.birch.UUUTalk.a` -> 后缀 `a`
- `com.birch.UUUTalk.b` -> 后缀 `b`
- `com.birch.UUUTalk.1` -> 后缀 `1`

也可在 `Info.plist` 中显式指定：

```xml
<key>UUUInstanceSuffix</key>
<string>custom</string>
```

## License

fishhook 部分遵循 Facebook 原始许可证，其余代码按 MIT 许可。
