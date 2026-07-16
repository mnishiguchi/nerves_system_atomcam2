################################################################################
#
# atomcam2-compat-headers
#
################################################################################

ATOMCAM2_COMPAT_HEADERS_VERSION = 1
ATOMCAM2_COMPAT_HEADERS_SITE = $(NERVES_DEFCONFIG_DIR)/package/atomcam2-compat-headers
ATOMCAM2_COMPAT_HEADERS_SITE_METHOD = local
ATOMCAM2_COMPAT_HEADERS_INSTALL_STAGING = YES
ATOMCAM2_COMPAT_HEADERS_INSTALL_TARGET = NO

define ATOMCAM2_COMPAT_HEADERS_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 \
		$(@D)/atomcam2-linux-3.10-compat.h \
		$(STAGING_DIR)/usr/include/atomcam2-linux-3.10-compat.h
endef

$(eval $(generic-package))
