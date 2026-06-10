INSTALL_TARGET_PROCESSES = SpringBoard

# 目标架构，针对非越狱签名，编 arm64 即可
ARCHS = arm64
TARGET = iphone:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = UUUTalkFix

# 把所有源文件都加进来共同编译
UUUTalkFix_FILES = Tweak.x UUUKeychainHook.m fishhook.c

# 必须引入 Security 框架，否则 Keychain Hook 编译报错
UUUTalkFix_FRAMEWORKS = UIKit Foundation Security UserNotifications AudioToolbox AVFoundation

# 开启 ARC
UUUTalkFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
