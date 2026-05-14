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

# ============= 5. Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi

# ============= 6. 第三方自定义软件包 =============
CUSTOM_PACKAGES=""
BINARY_PACKAGES=""
if [ -f "$REPO_ROOT/shell/custom-packages.sh" ]; then
    . "$REPO_ROOT/shell/custom-packages.sh"
    apply_custom_packages
fi

# ============= 7. 二进制 ipk 注入 =============
if [ -f "$REPO_ROOT/shell/prepare-binary.sh" ]; then
    . "$REPO_ROOT/shell/prepare-binary.sh"
    prepare_binary_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
fi

# ============= 8. ISTORE 商店（二进制 .run 包） =============
if echo "$BINARY_PACKAGES" | grep -q "luci-app-store"; then
    if [ -f "$REPO_ROOT/shell/prepare-store.sh" ]; then
        . "$REPO_ROOT/shell/prepare-store.sh"
        prepare_store_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
    fi
fi

echo "=== diy-part2.sh 完成 ==="
