################################################################################
#
# v4l2rtspserver
#
# RTSP server that publishes the already-encoded frames the vendor camera
# runtime writes into the v4l2loopback devices. Video only: the control
# kernel provides OSS rather than ALSA, so audio capture is not built.
#
################################################################################

V4L2RTSPSERVER_VERSION = ce808915edfd9ec934af351efe739dd9a07a07e5
V4L2RTSPSERVER_SITE = https://github.com/mpromonet/v4l2rtspserver.git
V4L2RTSPSERVER_SITE_METHOD = git
V4L2RTSPSERVER_LICENSE = Unlicense
V4L2RTSPSERVER_LICENSE_FILES = LICENSE
V4L2RTSPSERVER_DEPENDENCIES = live555 v4l2cpp
V4L2RTSPSERVER_CFLAGS = $(TARGET_CFLAGS) -DVERSION=1

define V4L2RTSPSERVER_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		EXTRA_CXXFLAGS="$(V4L2RTSPSERVER_CFLAGS)" \
		PREFIX="$(STAGING_DIR)/usr" -C $(@D) all
endef

define V4L2RTSPSERVER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/v4l2rtspserver \
		$(TARGET_DIR)/usr/bin/v4l2rtspserver
endef

$(eval $(generic-package))
