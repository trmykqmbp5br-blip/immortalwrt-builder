#!/bin/bash
# scripts/kernel-config.sh — 内核选项分治版
set -euo pipefail

# ==========================================
# 动态检测 target kernel config 文件路径
# ==========================================
# OpenWrt 目录结构: target/linux/x86/64/config-6.18
TARGET_DIR="target/linux/x86/64"
KERNEL_CONFIG=$(ls "${TARGET_DIR}"/config-* 2>/dev/null | head -1)

if [ -z "$KERNEL_CONFIG" ]; then
    echo "❌ 致命错误: 未找到 x86/64 内核配置文件 (target/linux/x86/64/config-*)"
    exit 1
fi

echo "📌 检测到内核配置文件: $KERNEL_CONFIG"

# ==========================================
# 定义要追加的内核选项
# ==========================================
KERNEL_OPTS=(
    "CONFIG_IA32_EMULATION=y"
)

if [ "${INCLUDE_DOCKER:-no}" = "yes" ]; then
    echo "==> 追加 Docker 相关内核选项..."
    KERNEL_OPTS+=(
        # 网络虚拟化
        "CONFIG_VETH=y"
        "CONFIG_MACVLAN=y"
        "CONFIG_IPVLAN=y"
        "CONFIG_VXLAN=y"
        # Netfilter / IPVS
        "CONFIG_IP_VS=y"
        "CONFIG_IP_VS_NFCT=y"
        "CONFIG_IP_VS_RR=y"
        "CONFIG_NF_NAT=y"
        # Cgroup
        "CONFIG_CGROUP_DEVICE=y"
        "CONFIG_CGROUP_PERF=y"
        "CONFIG_CGROUP_NET_PRIO=y"
        "CONFIG_CGROUP_NET_CLASSID=y"
    )
fi

# ==========================================
# 追加到内核配置文件（不重复追加）
# ==========================================
for opt in "${KERNEL_OPTS[@]}"; do
    key="${opt%%=*}"
    # 先删除已有行（包括 "=y", "=m", "# ... is not set" 形式）
    sed -i "/^${key}=/d; /^# ${key} /d" "$KERNEL_CONFIG"
    # 追加新行
    echo "$opt" >> "$KERNEL_CONFIG"
done

echo "✅ 内核选项已写入 $KERNEL_CONFIG"
