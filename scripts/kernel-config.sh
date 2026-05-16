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

# 在 Kernel/Configure/Default 末尾注入 olddefconfig，自动填充 NEW 选项默认值
# 防止 kernel 版本升级引入的新选项导致 syncconfig exit 2
patch_kernel_defaults_olddefconfig() {
    local MK="$1"
    [ -f "$MK" ] || { echo "WARNING: $MK not found, olddefconfig injection skipped"; return; }
    command -v python3 >/dev/null 2>&1 || { echo "WARNING: python3 not found, olddefconfig injection skipped"; return; }

    if grep -q "^	\$(KERNEL_MAKE) olddefconfig" "$MK" 2>/dev/null; then
        echo "  olddefconfig already patched in $MK"
        return
    fi

    # 在 vermagic 行之后插入 olddefconfig
    python3 <<-PYEOF
content = open("$MK", "r").read()
old = "MKHASH) md5 > \$(LINUX_DIR)/.vermagic\nendef"
new = "MKHASH) md5 > \$(LINUX_DIR)/.vermagic\n\t\$(KERNEL_MAKE) olddefconfig 2>&1\nendef"
if new not in content:
    content = content.replace(old, new)
    open("$MK", "w").write(content)
    print("  olddefconfig injected into $MK")
else:
    print("  olddefconfig already present in $MK")
PYEOF
}

# 统一预设内核选项，避免 syncconfig 交互式询问导致编译失败
# 格式: OPTION=VALUE（VALUE=disabled 表示禁用该选项）
for KERNEL_CONFIG in target/linux/x86/config-6.6 target/linux/x86/64/config-6.6; do
    [ -f "$KERNEL_CONFIG" ] || continue
    for entry in NET_9P_XEN=disabled ARCH_MMAP_RND_COMPAT_BITS=8 XFRM_USER_COMPAT=disabled; do
        opt="${entry%%=*}"
        val="${entry#*=}"
        if [ "$val" = "disabled" ]; then
            if ! grep -q "^# $opt is not set$\|^$opt=" "$KERNEL_CONFIG" 2>/dev/null; then
                echo "# $opt is not set" >> "$KERNEL_CONFIG"
                echo "  $opt disabled ($KERNEL_CONFIG)"
            fi
        else
            if ! grep -q "^$opt=" "$KERNEL_CONFIG" 2>/dev/null; then
                echo "$opt=$val" >> "$KERNEL_CONFIG"
                echo "  $opt=$val ($KERNEL_CONFIG)"
            fi
        fi
    done
done

# Inject olddefconfig to auto-fill NEW kernel options
patch_kernel_defaults_olddefconfig "include/kernel-defaults.mk"

patch_docker_support() {
    local KERNEL_CONFIG="$1"
    [ -f "$KERNEL_CONFIG" ] || return 0

    cat >> "$KERNEL_CONFIG" <<'EOF'

#
# Docker required / recommended kernel features
#

# cgroups + namespaces
CONFIG_CGROUPS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_SCHED=y
CONFIG_CPUSETS=y
CONFIG_MEMCG=y
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y

# veth + bridge
CONFIG_VETH=y
CONFIG_BRIDGE=y
CONFIG_BRIDGE_NETFILTER=y

# netfilter / iptables / NAT / conntrack
CONFIG_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_CONNTRACK_NETLINK=y
CONFIG_NF_NAT=y
CONFIG_NF_NAT_IPV4=y
CONFIG_NF_NAT_IPV6=y

CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_NAT=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_IP_NF_MATCH_CONNTRACK=y

CONFIG_IP6_NF_IPTABLES=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_MATCH_CONNTRACK=y

# physdev match (kmod-ipt-physdev)
CONFIG_IP_NF_MATCH_PHYSDEV=y

# IPVS (kmod-nf-ipvs)
CONFIG_IP_VS=y
CONFIG_IP_VS_RR=y
CONFIG_IP_VS_WRR=y
CONFIG_IP_VS_SH=y

# overlayfs (overlay2)
CONFIG_OVERLAY_FS=y

EOF
}

patch_docker_support "target/linux/x86/config-6.6"
patch_docker_support "target/linux/x86/64/config-6.6"
