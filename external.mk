# Project-specific compiled Buildroot packages can be added under package/*/.
# NERVES_DEFCONFIG_DIR is supplied by nerves_system_br while constructing the
# portable system artifact.
include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/package/*/*.mk))

# nerves-config assumes the Nerves external-toolchain layout. This system uses
# a Buildroot-built internal toolchain for now, so provide the small compatibility
# path that nerves-config needs to emit buildroot-gcc-args.
.PHONY: atomcam2-nerves-config-host-dir
atomcam2-nerves-config-host-dir:
	$(Q)mkdir -p $(HOST_DIR)/opt/ext-toolchain/bin
	$(Q)mkdir -p $(HOST_DIR)/bin
	$(Q)ln -sf ../opt/ext-toolchain/bin/echo-gcc-args $(HOST_DIR)/bin/echo-gcc-args.br_real

$(BUILD_DIR)/nerves-config-0.7/.stamp_target_installed: atomcam2-nerves-config-host-dir
