#!/bin/bash
# scripts/kernel-config.sh — 内核配置补丁 + Docker 内核依赖

cd /workdir/openwrt

# 1. 原有的 32 位内核支持 (保留)
./scripts/kconfig-tool --enable CONFIG_IA32_EMULATION

# 2. Docker 必需的内核依赖 (从原 BINARY_KERNEL_DEPS 移植)
# 网络与虚拟化支持
./scripts/kconfig-tool --enable CONFIG_VETH
./scripts/kconfig-tool --enable CONFIG_MACVLAN
./scripts/kconfig-tool --enable CONFIG_IPVLAN
./scripts/kconfig-tool --enable CONFIG_VXLAN
# Netfilter 路由追踪支持
./scripts/kconfig-tool --enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
./scripts/kconfig-tool --enable CONFIG_NETFILTER_XT_MATCH_IPVS
./scripts/kconfig-tool --enable CONFIG_IP_VS
./scripts/kconfig-tool --enable CONFIG_IP_VS_NFCT
./scripts/kconfig-tool --enable CONFIG_IP_VS_RR
# Cgroup 支持
./scripts/kconfig-tool --enable CONFIG_CGROUP_PIDS
./scripts/kconfig-tool --enable CONFIG_MEMCG

# 3. 委托 kernel-config-patch.py 注入 olddefconfig (保留)
python3 scripts/kernel-config-patch.py
