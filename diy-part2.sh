#!/bin/bash
# diy-part2.sh — 自定义配置编排器
# 由 GitHub Actions 在 openwrt/ 目录下调用（CWD = openwrt/）
# 按序加载 scripts/ 下的领域模块

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

echo "=== diy-part2.sh 开始 ==="

# ============= 修复有问题的 feed 包 Makefile =============
# luci-app-fchomo 的 Kconfig 有自引用递归依赖（depends on PACKAGE_luci-app-fchomo）
# .config 禁用由 config-manifest.sh 的 EXCLUDE 清单处理
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

# ============= 4. 统一包配置清单 =============
# config-manifest.sh 内部自动调用 apply_manifest() 写入 .config + 导出 BINARY_PACKAGES
. "$SCRIPTS_DIR/config-manifest.sh"

# ============= 5. Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi

# ============= 6. 二进制 ipk 注入 =============
if [ -f "$REPO_ROOT/shell/prepare-binary.sh" ]; then
    . "$REPO_ROOT/shell/prepare-binary.sh"
    prepare_binary_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
fi

# ============= 7. ISTORE 商店（二进制 .run 包） =============
if echo "$BINARY_PACKAGES" | grep -q "luci-app-store"; then
    if [ -f "$REPO_ROOT/shell/prepare-store.sh" ]; then
        . "$REPO_ROOT/shell/prepare-store.sh"
        prepare_store_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
    fi
fi

# ============= 8. x86 镜像 boot 目录修复 =============
# Build/combined 尝试从 staging_dir/boot/ 复制 config/System.map，
# 但 Kernel/Install 未定义，该目录永远为空。
# 改为直接从内核构建树复制。
if [ -f "target/linux/x86/image/Makefile" ]; then
    echo "=== 修复 x86 镜像 boot 目录源路径 ==="
    python3 "$REPO_ROOT/shell/fix-x86-boot.py" "target/linux/x86/image/Makefile" || \
        echo "  WARNING: x86 boot fix failed"
fi

echo "=== diy-part2.sh 完成 ==="

# 再次 make defconfig，让 OpenWrt 自动处理 Kconfig 依赖
make defconfig 2>/dev/null || true
