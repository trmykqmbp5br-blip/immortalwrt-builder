#!/bin/bash
# diy-part2.sh — 分治版
set -euo pipefail

# 赋予执行权限
chmod +x scripts/kconfig-tool scripts/*.sh

# ============================================================
# 阶段 1：补丁 Target Kernel Config（必须在 defconfig 之前！）
# ============================================================
echo "=========================================="
echo "阶段 1: 补丁内核配置文件"
echo "=========================================="
bash scripts/kernel-config.sh

# ============================================================
# 阶段 2：生成完整 .config（此时内核选项已包含在内）
# ============================================================
echo "=========================================="
echo "阶段 2: 生成基础配置"
echo "=========================================="
cat > .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
EOF

# defconfig 是安全的——因为 CCACHE 还没开启，不会被冲掉
echo "==> make defconfig（展开完整默认配置，含内核选项）"
make defconfig

# ============================================================
# 阶段 3：仅修改 OpenWrt 层配置（kconfig-tool）
# ============================================================
echo "=========================================="
echo "阶段 3: 注入 OpenWrt 层自定义配置"
echo "=========================================="
KCONFIG_TOOL="./scripts/kconfig-tool"

# --- CCACHE ---
CCACHE_DIR_PATH="${CCACHE_DIR:-/home/runner/.ccache}"
$KCONFIG_TOOL --enable CONFIG_CCACHE
$KCONFIG_TOOL --set-str CONFIG_CCACHE_DIR "$CCACHE_DIR_PATH"

# --- Rootfs 大小 ---
ROOTFS_SIZE="${ROOTFS_PARTSIZE:-1024}"
$KCONFIG_TOOL --set-val CONFIG_TARGET_ROOTFS_PARTSIZE "$ROOTFS_SIZE"

# --- 在此处添加其他 OpenWrt 层选项 ---
# 例：$KCONFIG_TOOL --enable PACKAGE_luci-app-docker

# ============================================================
# 阶段 4：解决依赖（只跑一次 olddefconfig，不需要任何 Makefile 补丁）
# ============================================================
echo "=========================================="
echo "阶段 4: 解决所有配置依赖"
echo "=========================================="
make olddefconfig

# 防御性校验：CCACHE 没被冲
if ! grep -q "CONFIG_CCACHE_DIR=\"$CCACHE_DIR_PATH\"" .config; then
    echo "❌ 错误: CCACHE 路径未正确写入 .config！"
    exit 1
fi

# 防御性校验：关键内核选项确实存在于 .config
for opt in CONFIG_IA32_EMULATION; do
    if ! grep -q "^${opt}=y" .config; then
        echo "⚠️ 警告: ${opt} 未在 .config 中生效，可能内核版本不兼容"
    fi
done

# ============================================================
# 阶段 5：32 位运行时注入（强依赖 + 严格校验）
# ============================================================
echo "=========================================="
echo "阶段 5: 32 位运行时注入"
echo "=========================================="

# --- musl32 ---
echo "==> 注入 musl 32-bit 运行时"
bash scripts/runtime-musl32.sh

# --- glibc32 (可选) ---
# bash scripts/runtime-glibc32.sh

# 严格校验：必须存在
check_file() {
    local file="$1"
    local desc="$2"
    if [ ! -e "$file" ]; then
        echo "❌ 致命错误: ${desc} 缺失: ${file}"
        echo "   构建终止。请检查 runtime tarball 是否存在且脚本正确。"
        exit 1
    fi
}

# musl32 关键文件
check_file "files/usr/bin/run-i386"    "32位启动器 run-i386"
check_file "files/lib/ld-musl-i386.so.1" "32位 musl 动态链接器"

# 如果启用了 glibc32
# check_file "files/lib32/glibc/ld-linux.so.2" "32位 glibc 动态链接器"

echo "✅ 32 位运行时注入并校验成功"
