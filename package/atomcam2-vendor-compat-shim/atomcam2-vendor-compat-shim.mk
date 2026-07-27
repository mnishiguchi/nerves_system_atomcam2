################################################################################
#
# atomcam2-vendor-compat-shim
#
################################################################################

ATOMCAM2_VENDOR_COMPAT_SHIM_VERSION = 1
ATOMCAM2_VENDOR_COMPAT_SHIM_SITE = $(NERVES_DEFCONFIG_DIR)/package/atomcam2-vendor-compat-shim
ATOMCAM2_VENDOR_COMPAT_SHIM_SITE_METHOD = local

define ATOMCAM2_VENDOR_COMPAT_SHIM_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) \
		-mips32r2 -mhard-float -Wa,-mhard-float \
		-Wall -Wextra -Werror \
		-fPIC -ffreestanding -fno-stack-protector \
		-fvisibility=hidden -nostdlib -nodefaultlibs \
		-shared -Wl,--hash-style=sysv -Wl,--no-undefined \
		-Wl,-soname,libatomcam2-vendor-compat-shim.so \
		-o $(@D)/libatomcam2-vendor-compat-shim.so \
		$(@D)/compat-shim.c
endef

define ATOMCAM2_VENDOR_COMPAT_SHIM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0555 \
		$(@D)/libatomcam2-vendor-compat-shim.so \
		$(TARGET_DIR)/usr/lib/atomcam2-vendor-camera/libcompat-shim.so
endef

$(eval $(generic-package))
