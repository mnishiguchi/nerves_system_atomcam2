################################################################################
#
# atomcam2-v4l2loopback
#
# Virtual V4L2 devices that carry already-encoded frames from the vendor
# camera runtime to the RTSP server. Pinned to the revision proven against
# Linux 3.10 by atomcam_tools; the version Buildroot ships requires a newer
# kernel API, which is why this is a separate package rather than the
# upstream one.
#
################################################################################

ATOMCAM2_V4L2LOOPBACK_VERSION = a6d82287eb734588a11c33e7281671c80c9bf6d7
ATOMCAM2_V4L2LOOPBACK_SITE = https://github.com/umlaeute/v4l2loopback.git
ATOMCAM2_V4L2LOOPBACK_SITE_METHOD = git
ATOMCAM2_V4L2LOOPBACK_LICENSE = GPL-2.0+
ATOMCAM2_V4L2LOOPBACK_LICENSE_FILES = COPYING

$(eval $(kernel-module))

define ATOMCAM2_V4L2LOOPBACK_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/lib/modules
	cp $(@D)/v4l2loopback.ko $(TARGET_DIR)/lib/modules/
endef

$(eval $(generic-package))
