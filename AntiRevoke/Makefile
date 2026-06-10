INSTALL_TARGET_PROCESSES = SpringBoard

ARCHS = arm64
TARGET = iphone:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiRevoke

AntiRevoke_FILES = Tweak.x

AntiRevoke_FRAMEWORKS = UIKit Foundation

AntiRevoke_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
