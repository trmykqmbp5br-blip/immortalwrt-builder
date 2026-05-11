#!/bin/bash
# custom-packages.sh — 第三方软件包选择
# 参考 CloudImageBuilder 风格，所有包默认注释，按需取消注释
#
# 使用减号前缀 "-" 可排除已选中的包
# 注意: imm 仓库内的包也在此统一管理去留

# ==================== imm 仓库插件 ====================
# 以下来自 ImmortalWrt 官方 feeds，编译时自动解析依赖
# 取消注释即可启用

# --- 磁盘/文件 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-diskman-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-filemanager-zh-cn"

# --- 网页终端 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ttyd-zh-cn"

# --- SFTP 服务器 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES openssh-sftp-server"

# --- 网络工具 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-upnp-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES socat"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES iperf3"

# --- IRQ 平衡 (多核路由优化) ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-irqbalance-zh-cn"

# --- 动态 DNS ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-ddns-zh-cn ddns-scripts-aliyun"

# --- ACME 证书 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-acme-zh-cn"

# --- Aria2 下载器 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-aria2-zh-cn"

# --- Argon 主题 + 配置 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"

# --- 高级设置 by sirpdboy (与 argon-config 冲突) ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-advancedplus luci-i18n-advancedplus-zh-cn -luci-app-argon-config -luci-i18n-argon-config-zh-cn"

# --- 分区扩容 by sirpdboy ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"

# --- Turbo ACC 网络加速 (集成 BBR/shortcut-fe) ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-turboacc"

# --- 任务计划 ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-taskplan luci-i18n-taskplan-zh-cn"

# --- MosDNS (替代 SmartDNS) ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-mosdns luci-i18n-mosdns-zh-cn"

# --- AdGuard Home ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-adguardhome"

# ==================== kenzo/small 第三方插件 (需启用 diy-part1.sh 中的 feed) ====================

# --- PassWall ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-passwall-zh-cn"

# --- HomeProxy ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-homeproxy-zh-cn"

# --- SSR-Plus (支持 mihomo) ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-ssr-plus luci-i18n-ssr-plus-zh-cn"

# --- OpenClash (需额外下载内核) ---
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# ==================== OpenClash 内核下载 (启用 OpenClash 时必须) ====================
# 以下由 build.sh 中的逻辑自动处理，此处无需手动添加

# ==================== iStore 商店 ====================
# 通过 workflow UI 选项 enable_store 控制，此处为占位
# 不要取消注释此行，由 workflow 自动注入
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-store"
