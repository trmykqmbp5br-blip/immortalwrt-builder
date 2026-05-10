#!/bin/bash
# diy-part2.sh - Custom config (runs after .config is loaded, before make defconfig)

# ============= 启用 IA32_EMULATION（32位应用支持）=============
KERNEL_CONFIG="target/linux/x86/config-6.6"
if [ -f "$KERNEL_CONFIG" ]; then
    if grep -q "CONFIG_IA32_EMULATION=y" "$KERNEL_CONFIG" 2>/dev/null; then
        echo "IA32_EMULATION already enabled in kernel config"
    else
        sed -i 's/.*CONFIG_IA32_EMULATION.*/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG" 2>/dev/null || true
        grep -q "CONFIG_IA32_EMULATION=y" "$KERNEL_CONFIG" 2>/dev/null || \
            echo "CONFIG_IA32_EMULATION=y" >> "$KERNEL_CONFIG"
        echo "IA32_EMULATION enabled in kernel config"
    fi
else
    echo "WARNING: Kernel config not found at $KERNEL_CONFIG"
fi

# ============= Docker 开关（根据 workflow 输入 INCLUDE_DOCKER）=============
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    echo "Enabling Docker packages..."
    sed -i 's/.*CONFIG_PACKAGE_dockerd.*/CONFIG_PACKAGE_dockerd=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker.*/CONFIG_PACKAGE_docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker-compose.*/CONFIG_PACKAGE_docker-compose=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-lib-docker.*/CONFIG_PACKAGE_luci-lib-docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-docker.*/CONFIG_PACKAGE_luci-app-docker=y/' .config
    # 确保 dockerman 也启用
    sed -i 's/.*CONFIG_PACKAGE_luci-app-dockerman.*/CONFIG_PACKAGE_luci-app-dockerman=y/' .config
else
    echo "Disabling Docker packages..."
    sed -i 's/.*CONFIG_PACKAGE_dockerd.*/# CONFIG_PACKAGE_dockerd is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker .*/# CONFIG_PACKAGE_docker is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker-compose.*/# CONFIG_PACKAGE_docker-compose is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-lib-docker.*/# CONFIG_PACKAGE_luci-lib-docker is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-docker.*/# CONFIG_PACKAGE_luci-app-docker is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-dockerman.*/# CONFIG_PACKAGE_luci-app-dockerman is not set/' .config
fi

# ============= Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi
