################################################################################
#
# atomcam2-video-hook
#
# Preloaded into the vendor camera runtime to mirror encoded frames into the
# v4l2loopback devices. Undefined symbols are intentionally left for the
# vendor process to resolve, so the library carries no libc of its own.
#
################################################################################

ATOMCAM2_VIDEO_HOOK_VERSION = 1
ATOMCAM2_VIDEO_HOOK_SITE = $(NERVES_DEFCONFIG_DIR)/package/atomcam2-video-hook
ATOMCAM2_VIDEO_HOOK_SITE_METHOD = local

define ATOMCAM2_VIDEO_HOOK_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) \
		-mips32r2 -mhard-float -Wa,-mhard-float \
		-Wall -Wextra -Werror \
		-fPIC -fno-stack-protector \
		-fvisibility=hidden -nostdlib -nodefaultlibs \
		-shared -Wl,--hash-style=sysv \
		-Wl,-soname,libatomcam2-video-hook.so \
		-o $(@D)/libatomcam2-video-hook.so \
		$(@D)/video-hook.c
endef

define ATOMCAM2_VIDEO_HOOK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0555 \
		$(@D)/libatomcam2-video-hook.so \
		$(TARGET_DIR)/usr/lib/atomcam2-vendor-camera/libvideo-hook.so
endef

$(eval $(generic-package))
