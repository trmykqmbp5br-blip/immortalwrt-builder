#!/bin/bash
# diy-part2.sh - 自定义配置 (在 .config 加载后、make defconfig 前运行)

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

# ============= 预置 32 位 musl 运行时 =============
# libc 是固件内置包，不在可下载的 packages 仓库中。
# 必须从官方 i386 (generic) rootfs 镜像提取 ld-musl-i386.so.1。
I386_ROOTFS_URL="https://downloads.immortalwrt.org/releases/24.10.6/targets/x86/generic/immortalwrt-24.10.6-x86-generic-generic-ext4-rootfs.img.gz"
LIBC32_TMP="/tmp/libc32_$$"
mkdir -p "$LIBC32_TMP" files/lib

echo "Fetching 32-bit musl runtime from i386 rootfs..."
if wget -q --timeout=60 -O "$LIBC32_TMP/rootfs.img.gz" "$I386_ROOTFS_URL" 2>/dev/null; then
    gunzip -f "$LIBC32_TMP/rootfs.img.gz" 2>/dev/null || true
    ROOTFS_IMG="$LIBC32_TMP/rootfs.img"
    if [ -f "$ROOTFS_IMG" ]; then
        debugfs -R "dump /lib/libc.so $LIBC32_TMP/ld-musl-i386.so.1" "$ROOTFS_IMG" 2>/dev/null
        if [ -f "$LIBC32_TMP/ld-musl-i386.so.1" ] && [ -s "$LIBC32_TMP/ld-musl-i386.so.1" ]; then
            cp "$LIBC32_TMP/ld-musl-i386.so.1" files/lib/ld-musl-i386.so.1
            echo "32-bit musl runtime extracted:"
            ls -la files/lib/ld-musl-i386.so.1
        else
            echo "WARNING: Could not extract libc.so from i386 rootfs"
        fi
    else
        echo "WARNING: Could not decompress i386 rootfs"
    fi
else
    echo "WARNING: Could not download i386 rootfs, skipping 32-bit runtime"
fi
rm -rf "$LIBC32_TMP"

# ============= Docker 开关 =============
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    echo "Enabling Docker packages..."
    sed -i 's/.*CONFIG_PACKAGE_dockerd.*/CONFIG_PACKAGE_dockerd=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker.*/CONFIG_PACKAGE_docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker-compose.*/CONFIG_PACKAGE_docker-compose=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-lib-docker.*/CONFIG_PACKAGE_luci-lib-docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-docker.*/CONFIG_PACKAGE_luci-app-docker=y/' .config
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

# ============= 第三方自定义软件包 =============
# diy-part2.sh 由 workflow 从 GITHUB_WORKSPACE 调用，CWD = openwrt/
# shell 脚本在仓库根目录的 shell/ 下
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CUSTOM_PACKAGES=""

if [ -f "$REPO_ROOT/shell/custom-packages.sh" ]; then
    . "$REPO_ROOT/shell/custom-packages.sh"
fi

# 处理 store .run 包（需在写入 .config 前完成 files/ 填充）
# 注意: files/ 已被 workflow 移动到 openwrt/files/，即当前目录下的 files/
if [ -n "$CUSTOM_PACKAGES" ] && echo "$CUSTOM_PACKAGES" | grep -q "luci-app-store"; then
    if [ -f "$REPO_ROOT/shell/prepare-store.sh" ]; then
        . "$REPO_ROOT/shell/prepare-store.sh"
        # files/ 相对于当前 CWD (openwrt/)
        prepare_store_packages "files" "$CUSTOM_PACKAGES"
        # store 包通过 files/ 直接植入 rootfs，不需要 CONFIG 条目
        CUSTOM_PACKAGES=$(echo "$CUSTOM_PACKAGES" | sed 's/luci-app-store//g' | xargs)
    fi
fi

# 将 CUSTOM_PACKAGES 写入 .config
if [ -n "$CUSTOM_PACKAGES" ]; then
    echo "=== 启用第三方软件包 ==="
    for pkg in $CUSTOM_PACKAGES; do
        # 处理排除项 (减号前缀)
        if echo "$pkg" | grep -q '^-'; then
            pkg_name=$(echo "$pkg" | sed 's/^-//')
            echo "  排除: $pkg_name"
            sed -i "s/.*CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/" .config 2>/dev/null || true
        else
            echo "  启用: $pkg"
            # 转换包名中的特殊字符为下划线
            pkg_conf=$(echo "$pkg" | sed 's/-/_/g')
            # 检查 .config 中是否已有此项
            if grep -q "CONFIG_PACKAGE_${pkg_conf}[= ]" .config 2>/dev/null; then
                sed -i "s/.*CONFIG_PACKAGE_${pkg_conf}.*/CONFIG_PACKAGE_${pkg_conf}=y/" .config
            else
                echo "CONFIG_PACKAGE_${pkg_conf}=y" >> .config
            fi
        fi
    done
    echo "=== 第三方包处理完毕 ==="
fi
