#!/bin/bash
# diy-part2.sh - Custom config (runs after .config is loaded, before make defconfig)

# ============= 启用 IA32_EMULATION（32位应用支持）=============
# 直接修改 ImmortalWrt 的 x86 内核配置文件
KERNEL_CONFIG="target/linux/x86/config-6.6"
if [ -f "$KERNEL_CONFIG" ]; then
    # 检查是否已启用
    if grep -q "CONFIG_IA32_EMULATION=y" "$KERNEL_CONFIG" 2>/dev/null; then
        echo "IA32_EMULATION already enabled in kernel config"
    else
        # 替换 # CONFIG_IA32_EMULATION is not set → CONFIG_IA32_EMULATION=y
        sed -i 's/.*CONFIG_IA32_EMULATION.*/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG" 2>/dev/null || true
        # 如果配置行不存在，追加
        grep -q "CONFIG_IA32_EMULATION=y" "$KERNEL_CONFIG" 2>/dev/null || \
            echo "CONFIG_IA32_EMULATION=y" >> "$KERNEL_CONFIG"
        echo "IA32_EMULATION enabled in kernel config"
    fi
else
    echo "WARNING: Kernel config not found at $KERNEL_CONFIG"
fi

# 从 workflow 输入设置 rootfs 大小
# （已在 .config 中设置 CONFIG_TARGET_ROOTFS_PARTSIZE=1024）
