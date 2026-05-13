#!/bin/bash
# custom-packages.sh — 第三方软件包选择
#
# 以下列出了可集成到固件的第三方软件。
# 取消注释即可启用对应软件，使用减号前缀 "-" 可排除已选中的包。
#
# 注意: 源码编译模式下，大部分包来自 kenzo/small feeds(在 diy-part1.sh 中启用)。
#       少数仅提供二进制 ipk 的包(如 istore) 通过 prepare-store.sh 处理。

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
