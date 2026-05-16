#!/bin/bash
set -e

# ==========================================
# P0 防御：检查关键环境变量
# ==========================================
: "${GITHUB_WORKSPACE:?❌ 错误：环境变量 GITHUB_WORKSPACE 未定义！请确保在 GitHub Actions 环境中运行，或手动 export 该变量。}"

echo "✅ 环境变量检查通过，工作区: $GITHUB_WORKSPACE"

# diy-part2.sh — 自定义配置编排器
# 由 GitHub Actions 在 openwrt/ 目录下调用（CWD = openwrt/）
#
# 执行顺序：
#   1. 内核/运行时补丁 + 修复 Makefile
#   2. make defconfig（计算所有 Kconfig 依赖）
#   3. apply_manifest（./scripts/config --disable BINARY/EXCLUDE，--enable SOURCE + PROVIDES 虚拟包）
#      绝不再执行 make defconfig，否则 BINARY 禁用会被依赖树复活
#   4. 下载 ipk / 二次 make download

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

echo "=== diy-part2.sh 开始 ==="

# ccache 限制 5GB + 启用压缩
export CCACHE_MAXSIZE="5G"
export CCACHE_COMPRESS="true"

# ============= 1. 内核配置补丁 =============
. "$SCRIPTS_DIR/kernel-config.sh"

# ============= 2. 32 位运行时 =============
. "$SCRIPTS_DIR/runtime-musl32.sh"
. "$SCRIPTS_DIR/runtime-glibc32.sh"

# ============= 3. make defconfig =============
# CCACHE_DIR 注入：确保 OpenWrt 的 rules.mk export 的路径与 cache action 一致
sed -i '/^CONFIG_CCACHE_DIR=/d' .config 2>/dev/null || true
echo 'CONFIG_CCACHE_DIR="/home/runner/.ccache"' >> .config
make defconfig

# ============= 5. apply_manifest =============
# 使用 scripts/config --disable BINARY/EXCLUDE 包，--enable SOURCE 包
# 【关键】之后绝不再执行 make defconfig
# ==========================================
# P0 防御：严格检查配置加载与变量定义
# ==========================================

# 1. 强制检查 source 是否成功，失败则立刻中断
CONFIG_MANIFEST_PATH="$GITHUB_WORKSPACE/scripts/config-manifest.sh"
if ! source "$CONFIG_MANIFEST_PATH"; then
    echo "❌ 错误：无法加载 $CONFIG_MANIFEST_PATH！请检查文件是否存在及语法是否正确。"
    exit 1
fi

# 2. 为关键变量设置安全默认值（防止 source 成功但变量未定义的极端情况）
CONFIG_MANIFEST_BINARY="${CONFIG_MANIFEST_BINARY:-}"
CONFIG_MANIFEST_EXCLUDE="${CONFIG_MANIFEST_EXCLUDE:-}"
CONFIG_MANIFEST_SOURCE="${CONFIG_MANIFEST_SOURCE:-}"

# 3. 状态日志（非常重要，方便排查是否加载成了空值）
echo "✔️ Manifest 配置加载完成："
echo "  - BINARY 包数量: $(echo $CONFIG_MANIFEST_BINARY | wc -w)"
echo "  - EXCLUDE 包数量: $(echo $CONFIG_MANIFEST_EXCLUDE | wc -w)"
echo "  - SOURCE 包数量: $(echo $CONFIG_MANIFEST_SOURCE | wc -w)"

# 应用 manifest（此时即使变量为空，也是安全的空字符串，不会引发未定义行为）
apply_manifest "$CONFIG_MANIFEST_BINARY" "$CONFIG_MANIFEST_EXCLUDE" "$CONFIG_MANIFEST_SOURCE"


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

# ============= 8. IPK 依赖拓扑排序 =============
if [ -f "$SCRIPTS_DIR/sort-ipk-deps.py" ]; then
    echo "=== IPK 依赖拓扑排序 ==="
    python3 "$SCRIPTS_DIR/sort-ipk-deps.py" "$REPO_ROOT/files/etc/ipk-cache"
fi

# ============= 9. x86 镜像 boot 目录修复 =============
if [ -f "target/linux/x86/image/Makefile" ]; then
    echo "=== 修复 x86 镜像 boot 目录源路径 ==="
    python3 "$REPO_ROOT/shell/fix-x86-boot.py" "target/linux/x86/image/Makefile" || \
        echo "  WARNING: x86 boot fix failed"
fi

# ============= 11. 校验 BINARY 包内核依赖 =============
if [ -f "$SCRIPTS_DIR/verify-kernel-deps.sh" ]; then
    echo "=== 校验 BINARY 包内核依赖 ==="
    bash "$SCRIPTS_DIR/verify-kernel-deps.sh" || exit 1
fi

# ============= 11. 校验 BINARY 包前后端一致性 =============
if [ -f "$SCRIPTS_DIR/verify-pkg-consistency.sh" ]; then
    echo "=== 校验 BINARY 包前后端一致性 ==="
    bash "$SCRIPTS_DIR/verify-pkg-consistency.sh" || exit 1
fi

# ============= 11. 校验 BINARY 包前后端一致性 =============
if [ -d package/ ]; then
    echo "=== 二次下载新增包源码 ==="
    make download -j$(nproc) 2>/dev/null || \
        echo "  WARNING: secondary download had issues (non-fatal)"
fi

echo "=== diy-part2.sh 完成 ==="
