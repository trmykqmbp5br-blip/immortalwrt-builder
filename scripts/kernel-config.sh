#!/bin/bash
# scripts/kernel-config.sh — 内核配置补丁
# 由 diy-part2.sh source 调用，CWD = openwrt/
# IA32_EMULATION + 内核新增选项
#
# 注意：x86_64 和 i386 有各自独立的内核配置，都需要打补丁

patch_ia32_emulation() {
    local KERNEL_CONFIG="$1"
    if [ -f "$KERNEL_CONFIG" ]; then
        if grep -q "^CONFIG_IA32_EMULATION=y$" "$KERNEL_CONFIG" 2>/dev/null; then
            echo "IA32_EMULATION already enabled in $KERNEL_CONFIG"
        elif grep -q "^# CONFIG_IA32_EMULATION is not set$" "$KERNEL_CONFIG" 2>/dev/null; then
            sed -i 's/^# CONFIG_IA32_EMULATION is not set$/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG"
            echo "IA32_EMULATION enabled in $KERNEL_CONFIG"
        elif grep -q "CONFIG_IA32_EMULATION" "$KERNEL_CONFIG" 2>/dev/null; then
            sed -i 's/^.*CONFIG_IA32_EMULATION.*$/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG"
            echo "IA32_EMULATION fixed in $KERNEL_CONFIG"
        else
            echo "CONFIG_IA32_EMULATION=y" >> "$KERNEL_CONFIG"
            echo "IA32_EMULATION appended to $KERNEL_CONFIG"
        fi
    else
        echo "WARNING: Kernel config not found at $KERNEL_CONFIG"
    fi
}

# 同时打两个补丁：x86 公共 + x86_64 专有
patch_ia32_emulation "target/linux/x86/config-6.6"
patch_ia32_emulation "target/linux/x86/64/config-6.6"

# 补充内核新增选项，避免 syncconfig 交互式询问导致编译失败
for KERNEL_CONFIG in target/linux/x86/config-6.6 target/linux/x86/64/config-6.6; do
    [ -f "$KERNEL_CONFIG" ] || continue
    for opt in CONFIG_NET_9P_XEN; do
        if ! grep -q "^# $opt is not set$\|^$opt=" "$KERNEL_CONFIG" 2>/dev/null; then
            echo "# $opt is not set" >> "$KERNEL_CONFIG"
            echo "  $opt disabled ($KERNEL_CONFIG)"
        fi
    done
    # IA32_EMULATION → COMPAT 相关新选项，避免 syncconfig 交互式询问
    for opt in CONFIG_ARCH_MMAP_RND_COMPAT_BITS:8; do
        opt_name="${opt%%:*}"
        opt_val="${opt##*:}"
        if ! grep -q "^$opt_name=" "$KERNEL_CONFIG" 2>/dev/null; then
            echo "$opt_name=$opt_val" >> "$KERNEL_CONFIG"
            echo "  $opt_name=$opt_val ($KERNEL_CONFIG)"
        fi
    done
done
