#!/bin/bash
cd /workdir/openwrt

KERNEL_CONFIG_FILE="target/linux/x86/64/config-6.6"

# ==== 基础配置（始终启用）====
# 清除旧配置块 + 旧定义，再重新追加
sed -i '/^# === Custom: 32-bit support/,/^CONFIG_IA32_EMULATION=y$/d' "$KERNEL_CONFIG_FILE"
cat >> "$KERNEL_CONFIG_FILE" <<EOF

# === Custom: 32-bit support ===
CONFIG_IA32_EMULATION=y
EOF

# ==== Docker 内核依赖（仅在 INCLUDE_DOCKER=yes 时启用）====
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    # 清除旧配置块 + 旧定义
    sed -i '/^# === Custom: Docker required modules/,/^CONFIG_MEMCG=y$/d' "$KERNEL_CONFIG_FILE"

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
