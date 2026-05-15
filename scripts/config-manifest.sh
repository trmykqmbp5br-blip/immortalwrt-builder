#!/bin/bash
# scripts/config-manifest.sh — 统一包配置策略层
# 由 diy-part2.sh source 调用，CWD = openwrt/
#
# 三方包有两种方式进固件：
#   1. SOURCE — 从 feed 正常编译，选入 .config 即可
#   2. BINARY — 非 feed 包，下载 .ipk 到 files/etc/ipk-cache/，开机 opkg install
#      （gh:/gh-bin:/store: 来源）
#   BINARY 包在 .config 中禁用（避免 make 找不到 Makefile 报错）
#   SOURCE 包在 .config 中启用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载机制层
. "$SCRIPT_DIR/manifest-lib.sh"

# ==================== BINARY 包来源声明 ====================
# 只有非 feed 包才走 BINARY 路径（下载 ipk，开机安装）
declare -A BINARY_SOURCE

# gh:owner/repo — GitHub Releases（ipk 匹配）
BINARY_SOURCE[luci-app-openclash]="gh:vernesong/OpenClash"

# gh-bin:owner/repo:pattern:path — GitHub Releases（binary tar.gz，直接解压到 files/ 指定目录）
BINARY_SOURCE[speedtest-go]="gh-bin:librespeed/speedtest-go:speedtest-go_.*linux_amd64\\.tar\\.gz:usr/bin"

# store:special — iStore 商店（由 prepare-store.sh 处理）
BINARY_SOURCE[luci-app-store]="store:special"

# ==================== 源码编译包（来自 feed） ====================
CONFIG_MANIFEST_SOURCE=""

# --- DNS ---
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE smartdns"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-app-smartdns"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-smartdns-zh-cn"

# --- 实用工具 ---
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-diskman-zh-cn"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-filemanager-zh-cn"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-app-ttyd luci-i18n-ttyd-zh-cn"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE openssh-sftp-server"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-ddns-zh-cn ddns-scripts-aliyun ddns-scripts"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-acme-zh-cn luci-app-acme acme acme-acmesh acme-acmesh-dnsapi"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE socat"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE iperf3"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-irqbalance-zh-cn"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-i18n-upnp-zh-cn"
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE tcpdump"

# --- 主题 ---
CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"

# --- Docker（条件编译） ---
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE docker dockerd containerd runc tini docker-compose"
    CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-lib-docker luci-app-docker luci-i18n-docker-zh-cn"
    CONFIG_MANIFEST_SOURCE="$CONFIG_MANIFEST_SOURCE luci-app-dockerman luci-i18n-dockerman-zh-cn"
else
    # 不启用 Docker 时彻底排除
    CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE docker dockerd containerd runc tini docker-compose"
    CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE luci-lib-docker luci-app-docker luci-i18n-docker-zh-cn"
    CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# ==================== 二进制 ipk 包（非 feed） ====================
CONFIG_MANIFEST_BINARY="luci-app-openclash speedtest-go luci-app-store"

# ==================== 排除包（不要的 feed 包） ====================
CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE luci-app-fchomo"

# ==================== 应用清单 ====================
apply_manifest "$CONFIG_MANIFEST_BINARY" "$CONFIG_MANIFEST_EXCLUDE" "$CONFIG_MANIFEST_SOURCE"

# 导出 BINARY_PACKAGES（供 prepare-binary.sh 消费）
export BINARY_PACKAGES="$CONFIG_MANIFEST_BINARY"
