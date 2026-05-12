#!/bin/bash
# scripts/kernel-config.sh — 内核配置补丁
# 由 diy-part2.sh source 调用，CWD = openwrt/
# IA32_EMULATION + 内核新增选项

KERNEL_CONFIG="target/linux/x86/config-6.6"
if [ -f "$KERNEL_CONFIG" ]; then
    if grep -q "^CONFIG_IA32_EMULATION=y$" "$KERNEL_CONFIG" 2>/dev/null; then
        echo "IA32_EMULATION already enabled in kernel config"
    elif grep -q "^# CONFIG_IA32_EMULATION is not set$" "$KERNEL_CONFIG" 2>/dev/null; then
        sed -i 's/^# CONFIG_IA32_EMULATION is not set$/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG"
        echo "IA32_EMULATION uncommented in kernel config"
    elif grep -q "CONFIG_IA32_EMULATION" "$KERNEL_CONFIG" 2>/dev/null; then
        sed -i 's/^.*CONFIG_IA32_EMULATION.*$/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG"
        echo "IA32_EMULATION fixed in kernel config"
    else
        echo "CONFIG_IA32_EMULATION=y" >> "$KERNEL_CONFIG"
        echo "IA32_EMULATION appended to kernel config"
    fi
else
    echo "WARNING: Kernel config not found at $KERNEL_CONFIG"
fi

# 补充内核新增选项，避免 syncconfig 交互式询问导致编译失败
for opt in CONFIG_NET_9P_XEN; do
    if ! grep -q "^# $opt is not set$\|^$opt=" "$KERNEL_CONFIG" 2>/dev/null; then
        echo "# $opt is not set" >> "$KERNEL_CONFIG"
        echo "$opt disabled (kernel new option)"
    fi
done
