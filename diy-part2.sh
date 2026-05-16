#!/bin/bash
# diy-part2.sh — 自定义配置编排器
# 由 GitHub Actions 在 openwrt/ 目录下调用（CWD = openwrt/）
# 按序加载 scripts/ 下的领域模块

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

echo "=== diy-part2.sh 开始 ==="

# ============= 禁用有问题的包 =============
# 1. .config 层面禁用 fchomo
sed -i 's/.*CONFIG_PACKAGE_luci-app-fchomo.*/# CONFIG_PACKAGE_luci-app-fchomo is not set/' .config 2>/dev/null || true
# 2. 修复 Kconfig 层面的自引用递归依赖
#    (luci-app-fchomo 的 Makefile 有 "depends on PACKAGE_luci-app-fchomo")
for makefile in package/feeds/*/*/luci-app-fchomo/Makefile; do
    [ -f "$makefile" ] && sed -i 's/depends on.*PACKAGE_luci-app-fchomo/depends on +PACKAGE_luci-app-fchomo/' "$makefile" && \
        echo "  Fixed fchomo recursive dependency in $makefile"
done

# ============= 1. 内核配置补丁 =============
. "$SCRIPTS_DIR/kernel-config.sh"

# ============= 2. 32 位 musl 运行时 =============
. "$SCRIPTS_DIR/runtime-musl32.sh"

# ============= 3. 32 位 glibc 运行时 =============
. "$SCRIPTS_DIR/runtime-glibc32.sh"

# ============= 4. Docker 开关 =============
. "$SCRIPTS_DIR/docker-toggle.sh"

# Docker kmod 包（仅在 INCLUDE_DOCKER=yes 时启用）
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    echo "Enabling Docker kmod packages..."
    for kmod in \
        kmod-veth \
        kmod-bridge \
        kmod-nf-conntrack \
        kmod-nf-conntrack-netlink \
        kmod-nf-nat \
        kmod-nf-nat4 \
        kmod-nf-nat6 \
        kmod-ipt-core \
        kmod-ipt-nat \
        kmod-ipt-conntrack \
        kmod-ipt-physdev \
        kmod-ip6tables \
        kmod-ip6t-nat \
        kmod-ip-vs \
        kmod-overlay; do
        pkg_conf=$(echo "$kmod" | sed 's/-/_/g')
        if grep -q "CONFIG_PACKAGE_${pkg_conf}[= ]" .config 2>/dev/null; then
            sed -i "s/.*CONFIG_PACKAGE_${pkg_conf}.*/CONFIG_PACKAGE_${pkg_conf}=y/" .config
        else
            echo "CONFIG_PACKAGE_${pkg_conf}=y" >> .config
        fi
    done
    echo "  Docker kmod packages enabled"
fi

# ============= 5. Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi

# ============= 6. 第三方自定义软件包 =============
CUSTOM_PACKAGES=""

if [ -f "$REPO_ROOT/shell/custom-packages.sh" ]; then
    . "$REPO_ROOT/shell/custom-packages.sh"
fi

# 处理 store .run 包
if [ -n "$CUSTOM_PACKAGES" ] && echo "$CUSTOM_PACKAGES" | grep -q "luci-app-store"; then
    if [ -f "$REPO_ROOT/shell/prepare-store.sh" ]; then
        . "$REPO_ROOT/shell/prepare-store.sh"
        prepare_store_packages "files" "$CUSTOM_PACKAGES"
        CUSTOM_PACKAGES=$(echo "$CUSTOM_PACKAGES" | sed 's/luci-app-store//g' | xargs)
    fi
fi

# 写入 .config
if [ -n "$CUSTOM_PACKAGES" ]; then
    echo "=== 启用第三方软件包 ==="
    for pkg in $CUSTOM_PACKAGES; do
        if echo "$pkg" | grep -q '^-'; then
            pkg_name=$(echo "$pkg" | sed 's/^-//')
            echo "  排除: $pkg_name"
            sed -i "s/.*CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/" .config 2>/dev/null || true
        else
            echo "  启用: $pkg"
            pkg_conf=$(echo "$pkg" | sed 's/-/_/g')
            if grep -q "CONFIG_PACKAGE_${pkg_conf}[= ]" .config 2>/dev/null; then
                sed -i "s/.*CONFIG_PACKAGE_${pkg_conf}.*/CONFIG_PACKAGE_${pkg_conf}=y/" .config
            else
                echo "CONFIG_PACKAGE_${pkg_conf}=y" >> .config
            fi
        fi
    done
    echo "=== 第三方包处理完毕 ==="
fi

# ============= 7. CCACHE 配置 =============
KCONFIG_TOOL="./scripts/kconfig-tool"
# --- CCACHE ---
# 不再使用 CCACHE_DIR，直接写死和 Actions 一致的路径
CCACHE_DIR_PATH="/home/runner/.ccache"
$KCONFIG_TOOL --enable CONFIG_CCACHE
$KCONFIG_TOOL --set-str CONFIG_CCACHE_DIR "$CCACHE_DIR_PATH"

echo "=== diy-part2.sh 完成 ==="
