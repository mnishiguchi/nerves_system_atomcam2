################################################################################
#
# atomcam2-camera
#
# Prebuilt native camera daemon. It dynamically links the vendor libimp
# at runtime and therefore has to be built with the Ingenic uClibc
# toolchain, which Buildroot does not provide; README.md documents how to
# rebuild it from camd.c.
#
################################################################################

# Bump when the prebuilt binary changes: local-site packages are NOT
# rebuilt on file changes alone, so a stale binary ships silently
# otherwise.
ATOMCAM2_CAMERA_VERSION = 4
ATOMCAM2_CAMERA_SITE = $(NERVES_DEFCONFIG_DIR)/package/atomcam2-camera
ATOMCAM2_CAMERA_SITE_METHOD = local

define ATOMCAM2_CAMERA_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/atomcam2-camd \
		$(TARGET_DIR)/usr/bin/atomcam2-camd
endef

$(eval $(generic-package))
