################################################################################
# atomcam2-first-ssh
################################################################################

ATOMCAM2_FIRST_SSH_VERSION = 0.1.0
ATOMCAM2_FIRST_SSH_SITE = $(BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH)/package/atomcam2-first-ssh
ATOMCAM2_FIRST_SSH_SITE_METHOD = local

define ATOMCAM2_FIRST_SSH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH)/rootfs_overlay/usr/bin/atomcam2-env \
		$(TARGET_DIR)/usr/bin/atomcam2-env
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH)/rootfs_overlay/usr/bin/atomcam2-pre-run \
		$(TARGET_DIR)/usr/bin/atomcam2-pre-run
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH)/rootfs_overlay/usr/bin/atomcam2-wifi-driver \
		$(TARGET_DIR)/usr/bin/atomcam2-wifi-driver
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH)/rootfs_overlay/usr/bin/atomcam2-network-check \
		$(TARGET_DIR)/usr/bin/atomcam2-network-check
endef

$(eval $(generic-package))
