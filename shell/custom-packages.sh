#!/bin/bash
# custom-packages.sh — 第三方软件包选择 + 应用
# 由 diy-part2.sh source 调用，CWD = openwrt/
# 设置 CUSTOM_PACKAGES 变量，定义 apply_custom_packages() 写入 .config

# ==================== 代理/VPN 类 ====================
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-passwall-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-homeproxy-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ssr-plus luci-i18n-ssr-plus-zh-cn"

# ==================== 实用工具 ====================
# 磁盘管理
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-diskman-zh-cn"
# 文件管理器 (浏览器内管理文件)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-filemanager-zh-cn"
# 网页终端 ttyd
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-cn"
# SFTP 服务器 (方便传文件)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES openssh-sftp-server"
# DDNS 动态域名
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ddns-zh-cn ddns-scripts-aliyun ddns-scripts"
# ACME 证书管理
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-acme-zh-cn luci-app-acme acme acme-acmesh acme-acmesh-dnsapi"
# Aria2 下载器
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-aria2-zh-cn"
# socat (端口转发)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES socat"
# iperf3 网络测速
CUSTOM_PACKAGES="$CUSTOM_PACKAGES iperf3"
# IRQ 平衡 (多核路由优化)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-irqbalance-zh-cn"
# UPnP
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-upnp-zh-cn"
# 网络工具
CUSTOM_PACKAGES="$CUSTOM_PACKAGES speedtest-go tcpdump"

# ==================== 主题 ====================
# Argon 主题 + 配置
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"

# ==================== 网络服务 ====================
# MosDNS (替代 SmartDNS)
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mosdns luci-i18n-mosdns-zh-cn"
# AdGuard Home
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-adguardhome"

# ==================== 系统工具 ====================
# 高级设置 by sirpdboy (注意: 与 argon-config 冲突，启用时需排除 argon-config)
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-advancedplus luci-i18n-advancedplus-zh-cn -luci-app-argon-config -luci-i18n-argon-config-zh-cn"
# 分区扩容 by sirpdboy
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"
# Turbo ACC 网络加速 (集成 BBR/shortcut-fe)
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-turboacc"
# 任务计划
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-taskplan luci-i18n-taskplan-zh-cn"

# ==================== ISTORE 商店 (需二进制 ipk) ====================
# 启用 istore 需要同步勾选 workflow 中的 enable_store 选项
# 此处仅作占位，实际由 prepare-store.sh 处理
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-store"

# ================================================================
# apply_custom_packages — 校验并写入 CUSTOM_PACKAGES 到 .config
# CWD = openwrt/，.config 应已存在
# ================================================================
apply_custom_packages() {
    local pkg_list="$CUSTOM_PACKAGES"

    # -- 预处理: store 包 —
    if echo "$pkg_list" | grep -q "luci-app-store"; then
        if [ -f "$REPO_ROOT/shell/prepare-store.sh" ]; then
            . "$REPO_ROOT/shell/prepare-store.sh"
            prepare_store_packages "files" "$pkg_list"
            pkg_list=$(echo "$pkg_list" | sed 's/luci-app-store//g' | xargs)
        fi
    fi

    [ -z "$pkg_list" ] && return

    echo "=== 启用第三方软件包 ==="
    for pkg in $pkg_list; do
        if echo "$pkg" | grep -q '^-'; then
            # 排除项
            pkg_name=$(echo "$pkg" | sed 's/^-//')
            echo "  排除: $pkg_name"
            sed -i "s/.*CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/" .config 2>/dev/null || true
        else
            # 校验: 检查 feeds 或 base 中是否存在该包的 Makefile
            local found=false
            for try_path in "package/feeds/*/$pkg/Makefile" "package/$pkg/Makefile"; do
                for f in $try_path; do
                    [ -f "$f" ] && { found=true; break; }
                done
                $found && break
            done

            if ! $found; then
                echo "  WARNING: $pkg 在 feeds 中未找到，跳过"
                continue
            fi

            echo "  启用: $pkg"
            # .config 中用连字符（如 CONFIG_PACKAGE_luci-app-openclash=y），不转下划线
            if grep -q "CONFIG_PACKAGE_${pkg}[= ]" .config 2>/dev/null; then
                sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/CONFIG_PACKAGE_${pkg}=y/" .config
            else
                echo "CONFIG_PACKAGE_${pkg}=y" >> .config
            fi
        fi
    done
    echo "=== 第三方包处理完毕 ==="
}
