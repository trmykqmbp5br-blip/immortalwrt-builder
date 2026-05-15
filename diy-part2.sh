#!/bin/bash
# diy-part2.sh — 自定义配置编排器
# 由 GitHub Actions 在 openwrt/ 目录下调用（CWD = openwrt/）
#
# 执行顺序：
#   1. 内核/运行时补丁 + 修复 Makefile
#   2. 生成 PROVIDES 虚拟包（custom-binary-provides）
#   3. make defconfig（计算所有 Kconfig 依赖）
#   4. apply_manifest（./scripts/config --disable BINARY/EXCLUDE，--enable SOURCE + PROVIDES 虚拟包）
#      绝不再执行 make defconfig，否则 BINARY 禁用会被依赖树复活
#   5. 下载 ipk / 二次 make download

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

echo "=== diy-part2.sh 开始 ==="

# ccache 限制 5GB + 启用压缩
export CCACHE_MAXSIZE="5G"
export CCACHE_COMPRESS="true"

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

# ============= 3. 生成 PROVIDES 虚拟包 =============
# 读取 BINARY 包列表，生成 custom-binary-provides 的 PROVIDES 行
# 这个包编译为空，但通过 PROVIDES 让依赖系统以为这些包已存在
. "$SCRIPTS_DIR/binary-packages.sh" 2>/dev/null || true
mkdir -p package/custom-provides
if [ -f "$REPO_ROOT/package/custom-provides/Makefile" ]; then
    sed "s/PROVIDES:=/PROVIDES:=$BINARY_PACKAGES_FLAT/" \
        "$REPO_ROOT/package/custom-provides/Makefile" > package/custom-provides/Makefile
    echo "  Generated package/custom-provides/Makefile with $(echo $BINARY_PACKAGES_FLAT | wc -w) providers"
fi

# ============= 4. make defconfig =============
# CCACHE_DIR 注入：确保 OpenWrt 的 rules.mk export 的路径与 cache action 一致
sed -i '/^CONFIG_CCACHE_DIR=/d' .config 2>/dev/null || true
echo 'CONFIG_CCACHE_DIR="/home/runner/.ccache"' >> .config
make defconfig

# ============= 5. apply_manifest =============
# 使用 scripts/config --disable BINARY/EXCLUDE 包，--enable SOURCE 包
# 【关键】之后绝不再执行 make defconfig
. "$SCRIPTS_DIR/config-manifest.sh"
apply_manifest "$CONFIG_MANIFEST_BINARY" "$CONFIG_MANIFEST_EXCLUDE" "$CONFIG_MANIFEST_SOURCE"

# 启用 PROVIDES 虚拟包（编译空包但 PROVIDES 所有 BINARY 包）
./scripts/config --enable "CONFIG_PACKAGE_custom-binary-provides" 2>/dev/null || true

# ============= 6. Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi

# ============= 7. 二进制 ipk 下载 =============
if [ -f "$REPO_ROOT/shell/prepare-binary.sh" ]; then
    . "$REPO_ROOT/shell/prepare-binary.sh"
    prepare_binary_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
fi

# ============= 8. x86 镜像 boot 目录修复 =============
if [ -f "target/linux/x86/image/Makefile" ]; then
    echo "=== 修复 x86 镜像 boot 目录源路径 ==="
    python3 "$REPO_ROOT/shell/fix-x86-boot.py" "target/linux/x86/image/Makefile" || \
        echo "  WARNING: x86 boot fix failed"
fi

# ============= 9. 二次 make download =============
if [ -d package/ ]; then
    echo "=== 二次下载新增包源码 ==="
    make download -j$(nproc) 2>/dev/null || \
        echo "  WARNING: secondary download had issues (non-fatal)"
fi

echo "=== diy-part2.sh 完成 ==="
