#!/bin/bash
cd /workdir/openwrt

# 自动探测 x86/64 下的内核配置文件
KERNEL_CONFIG_FILE=$(ls target/linux/x86/64/config-* 2>/dev/null | head -n 1)

if [ -z "$KERNEL_CONFIG_FILE" ]; then
    echo "❌ Error: Kernel config file not found in target/linux/x86/64/"
    exit 1
fi

echo "📌 Patching kernel config: $KERNEL_CONFIG_FILE"

# ==== 基础配置（始终启用）====
cat >> "$KERNEL_CONFIG_FILE" <<EOF

# === Custom: 32-bit support ===
CONFIG_IA32_EMULATION=y
EOF

# ==== Docker 内核依赖（仅在 INCLUDE_DOCKER=yes 时启用）====
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    cat >> "$KERNEL_CONFIG_FILE" <<DOCKEREOF

# === Custom: Docker required modules ===
CONFIG_VETH=y
CONFIG_MACVLAN=y
CONFIG_IPVLAN=y
CONFIG_VXLAN=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_MATCH_IPVS=y
CONFIG_IP_VS=y
CONFIG_IP_VS_NFCT=y
CONFIG_IP_VS_RR=y
CONFIG_CGROUP_PIDS=y
CONFIG_MEMCG=y
DOCKEREOF
fi
