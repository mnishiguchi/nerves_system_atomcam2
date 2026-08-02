################################################################################
#
# v4l2cpp
#
# C++ V4L2 wrapper library used by v4l2rtspserver.
#
################################################################################

V4L2CPP_VERSION = 3eff050e79e76eecd240a07e5406f0787ca4af3f
V4L2CPP_SITE = https://github.com/mpromonet/libv4l2cpp
V4L2CPP_SITE_METHOD = git
V4L2CPP_LICENSE = Unlicense
V4L2CPP_LICENSE_FILES = LICENSE
V4L2CPP_INSTALL_STAGING = YES
V4L2CPP_DEPENDENCIES = log4cpp
V4L2CPP_CFLAGS = $(TARGET_CFLAGS) -fPIC

define V4L2CPP_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		AR="$(TARGET_AR)" EXTRA_CXXFLAGS="$(V4L2CPP_CFLAGS)" -C $(@D) all
endef

define V4L2CPP_INSTALL_STAGING_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) PREFIX="$(STAGING_DIR)/usr" -C $(@D) install
endef

define V4L2CPP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libv4l2wrapper.so \
		$(TARGET_DIR)/usr/lib/libv4l2wrapper.so
endef

$(eval $(generic-package))
