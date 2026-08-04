################################################################################
#
# atomcam2-boot-announce
#
# Prebuilt speaker playback tool and the boot announcement sound. The
# player dynamically links the vendor libimp at runtime and therefore has
# to be built with the Ingenic uClibc toolchain, which Buildroot does not
# provide; README.md documents how to rebuild it from aoplay.c.
#
################################################################################

# Bump when the prebuilt payloads change: local-site packages are NOT
# rebuilt on file changes alone.
ATOMCAM2_BOOT_ANNOUNCE_VERSION = 2
ATOMCAM2_BOOT_ANNOUNCE_SITE = $(NERVES_DEFCONFIG_DIR)/package/atomcam2-boot-announce
ATOMCAM2_BOOT_ANNOUNCE_SITE_METHOD = local

define ATOMCAM2_BOOT_ANNOUNCE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/atomcam2-aoplay \
		$(TARGET_DIR)/usr/bin/atomcam2-aoplay
	$(INSTALL) -D -m 0644 $(@D)/boot-announce.raw \
		$(TARGET_DIR)/usr/share/atomcam2/boot-announce.raw
endef

$(eval $(generic-package))
