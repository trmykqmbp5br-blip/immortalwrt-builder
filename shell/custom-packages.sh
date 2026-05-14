#!/bin/bash
# custom-packages.sh — 第三方软件包选择（全部二进制注入）
#
# 所有第三方包都通过 prepare-binary.sh 下载 ipk 并解压到 files/，
# 编译时直接打包进 rootfs，不需要源码编译。
#
# Feed 源码包（通过 .config 启用）:
#   CUSTOM_PACKAGES="$CUSTOM_PACKAGES <pkg>"
# 二进制 ipk 注入包（通过 prepare-binary.sh 处理）:
#   BINARY_PACKAGES="$BINARY_PACKAGES <pkg>"

# ==================== 代理/VPN ====================
BINARY_PACKAGES="$BINARY_PACKAGES luci-app-openclash"

# ==================== DNS ====================
BINARY_PACKAGES="$BINARY_PACKAGES smartdns"
BINARY_PACKAGES="$BINARY_PACKAGES luci-app-smartdns"
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-smartdns-zh-cn"

# ==================== 实用工具 ====================
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-diskman-zh-cn"
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-filemanager-zh-cn"
BINARY_PACKAGES="$BINARY_PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-cn"
BINARY_PACKAGES="$BINARY_PACKAGES openssh-sftp-server"
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-ddns-zh-cn ddns-scripts-aliyun ddns-scripts"
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-acme-zh-cn luci-app-acme acme acme-acmesh acme-acmesh-dnsapi"
BINARY_PACKAGES="$BINARY_PACKAGES socat"
BINARY_PACKAGES="$BINARY_PACKAGES iperf3"
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-irqbalance-zh-cn"
BINARY_PACKAGES="$BINARY_PACKAGES luci-i18n-upnp-zh-cn"
BINARY_PACKAGES="$BINARY_PACKAGES speedtest-go tcpdump"

# ==================== 主题 ====================
BINARY_PACKAGES="$BINARY_PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"

# ==================== Docker ====================
# Docker 全家桶全部二进制注入，避免 Go 源码编译耗时长 + 依赖断裂
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    BINARY_PACKAGES="$BINARY_PACKAGES docker dockerd containerd runc tini docker-compose"
    BINARY_PACKAGES="$BINARY_PACKAGES luci-lib-docker luci-app-docker luci-i18n-docker-zh-cn"
    BINARY_PACKAGES="$BINARY_PACKAGES luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# ==================== 商店 ====================
BINARY_PACKAGES="$BINARY_PACKAGES luci-app-store"

# ================================================================
# apply_custom_packages — 将 CUSTOM_PACKAGES 中的 feed 包写入 .config
# CWD = openwrt/
# ================================================================
apply_custom_packages() {
    local pkg_list="$CUSTOM_PACKAGES"
    [ -z "$pkg_list" ] && return

    echo "=== 启用第三方软件包 ==="
    for pkg in $pkg_list; do
        if echo "$pkg" | grep -q '^-'; then
            pkg_name=$(echo "$pkg" | sed 's/^-//')
            echo "  排除: $pkg_name"
            sed -i "s/.*CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/" .config 2>/dev/null || true
        else
            echo "  启用: $pkg"
            if grep -q "CONFIG_PACKAGE_${pkg}[= ]" .config 2>/dev/null; then
                sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/CONFIG_PACKAGE_${pkg}=y/" .config
            else
                echo "CONFIG_PACKAGE_${pkg}=y" >> .config
            fi
        fi
    done
    echo "=== 第三方包处理完毕 ==="
}
