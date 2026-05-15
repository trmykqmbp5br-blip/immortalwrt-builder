#!/bin/bash
# diy-part2.sh — 自定义配置编排器
# 由 GitHub Actions 在 openwrt/ 目录下调用（CWD = openwrt/）
# 按序加载 scripts/ 下的领域模块
#
# 执行顺序：
#   1. 内核/运行时补丁
#   2. make defconfig（计算所有 Kconfig 依赖）
#   3. apply_manifest（scripts/config --disable BINARY 包，--enable SOURCE 包）
#      重要：之后绝不再执行 make defconfig，否则 BINARY 禁用会被 Kconfig 依赖复活
#   4. 下载 ipk / 二次 make download
#   5. 编译

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

echo "=== diy-part2.sh 开始 ==="

# ============= 修复有问题的 feed 包 Makefile =============
for makefile in package/feeds/*/*/luci-app-fchomo/Makefile; do
    [ -f "$makefile" ] && sed -i 's/depends on.*PACKAGE_luci-app-fchomo/depends on +PACKAGE_luci-app-fchomo/' "$makefile" && \
        echo "  Fixed fchomo recursive dependency in $makefile"
done

# ============= 1. 内核配置补丁 =============
. "$SCRIPTS_DIR/kernel-config.sh"

# ============= 2. 32 位运行时 =============
. "$SCRIPTS_DIR/runtime-musl32.sh"
. "$SCRIPTS_DIR/runtime-glibc32.sh"

# ============= 3. make defconfig — 让 OpenWrt 自动补全 Kconfig 依赖 =============
# 此时 BINARY/SOURCE 包尚未被 apply_manifest 修改，
# make defconfig 能看到所有包的依赖关系并正确计算。
# 这也是 CCACHE_DIR 注入的最佳时机——defconfig 会保留已设值。
sed -i '/^CONFIG_CCACHE_DIR=/d' .config 2>/dev/null || true
echo 'CONFIG_CCACHE_DIR="/home/runner/.ccache"' >> .config
make defconfig

# ============= 4. apply_manifest — 统一包配置 =============
# 使用 scripts/config --disable（精确 key 操作，非 sed 子串匹配）
# 禁用所有 BINARY/EXCLUDE 包，启用 SOURCE 包。
# 【关键】之后绝不再执行 make defconfig，否则 Kconfig 引擎会根据
#   depends on/select 关系把 BINARY 包复活。
. "$SCRIPTS_DIR/config-manifest.sh"
apply_manifest "$CONFIG_MANIFEST_BINARY" "$CONFIG_MANIFEST_EXCLUDE" "$CONFIG_MANIFEST_SOURCE"

# ============= 5. Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi

# ============= 6. 二进制 ipk 下载 =============
if [ -f "$REPO_ROOT/shell/prepare-binary.sh" ]; then
    . "$REPO_ROOT/shell/prepare-binary.sh"
    prepare_binary_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
fi

# ============= 7. x86 镜像 boot 目录修复 =============
if [ -f "target/linux/x86/image/Makefile" ]; then
    echo "=== 修复 x86 镜像 boot 目录源路径 ==="
    python3 "$REPO_ROOT/shell/fix-x86-boot.py" "target/linux/x86/image/Makefile" || \
        echo "  WARNING: x86 boot fix failed"
fi

# ============= 8. 二次 make download =============
# 某些包（如 kenzo/small feed 中的）可能在上次 make download 之后才添加，
# 这里补下载。不阻塞——下载失败会在后面 make 时重试。
if [ -d package/ ]; then
    echo "=== 二次下载新增包源码 ==="
    make download -j$(nproc) 2>/dev/null || \
        echo "  WARNING: secondary download had issues (non-fatal)"
fi

echo "=== diy-part2.sh 完成 ==="
