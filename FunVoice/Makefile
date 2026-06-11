INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64
TARGET = iphone:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FunVoice

FunVoice_FILES = Tweak.x
FunVoice_FRAMEWORKS = UIKit Foundation AVFoundation MobileCoreServices
FunVoice_CFLAGS = -fobjc-arc -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/tweak.mk
