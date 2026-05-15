#!/bin/bash
# scripts/config-manifest.sh — 统一包配置策略层
# 由 diy-part2.sh source 调用，CWD = openwrt/
#
# BINARY — .config 禁用这些包，不编译。
#   从 feed / GitHub 下载预编译 ipk 到 files/etc/ipk-cache/，
#   首次启动时 opkg install --force-depends。
#   来源声明在 BINARY_SOURCE 关联数组中。
#
# SOURCE — 从 feed 正常编译，仅用于需要显式启用但又不在 .config 默认列表中的包。
#
# EXCLUDE — 彻底禁用，不编译不安装。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 加载 BINARY 包扁平列表（用于 PROVIDES 虚拟包生成）
. "$SCRIPT_DIR/binary-packages.sh"
. "$SCRIPT_DIR/manifest-lib.sh"

declare -A BINARY_SOURCE

# ==================== BINARY 包来源声明 ====================
# 格式：
#   feed:{luci,packages,base} — ImmortalWrt 官方 feed（USTC 镜像）
#   gh:owner/repo — GitHub Releases（ipk 匹配）
#   gh-bin:owner/repo:pattern:path — GitHub binary tar.gz（解压到 files/ 指定目录）
#   store:special — iStore 商店（由 prepare-store.sh 处理）

# --- 代理/VPN ---
BINARY_SOURCE[luci-app-openclash]="gh:vernesong/OpenClash"

# --- DNS ---
BINARY_SOURCE[smartdns]="feed:packages"
BINARY_SOURCE[luci-app-smartdns]="feed:luci"
BINARY_SOURCE[luci-i18n-smartdns-zh-cn]="feed:luci"

# --- 实用工具 ---
BINARY_SOURCE[luci-i18n-diskman-zh-cn]="feed:luci"
BINARY_SOURCE[luci-i18n-filemanager-zh-cn]="feed:luci"
BINARY_SOURCE[luci-app-ttyd]="feed:luci"
BINARY_SOURCE[luci-i18n-ttyd-zh-cn]="feed:luci"
BINARY_SOURCE[openssh-sftp-server]="feed:packages"
BINARY_SOURCE[luci-i18n-ddns-zh-cn]="feed:luci"
BINARY_SOURCE[ddns-scripts-aliyun]="feed:packages"
BINARY_SOURCE[ddns-scripts]="feed:packages"
BINARY_SOURCE[luci-i18n-acme-zh-cn]="feed:luci"
BINARY_SOURCE[luci-app-acme]="feed:luci"
BINARY_SOURCE[acme]="feed:packages"
BINARY_SOURCE[acme-acmesh]="feed:packages"
BINARY_SOURCE[acme-acmesh-dnsapi]="feed:packages"
BINARY_SOURCE[socat]="feed:packages"
BINARY_SOURCE[iperf3]="feed:packages"
BINARY_SOURCE[luci-i18n-irqbalance-zh-cn]="feed:luci"
BINARY_SOURCE[luci-i18n-upnp-zh-cn]="feed:luci"
BINARY_SOURCE[speedtest-go]="feed:packages"
BINARY_SOURCE[tcpdump]="feed:base"

# --- 主题 ---
BINARY_SOURCE[luci-theme-argon]="feed:luci"
BINARY_SOURCE[luci-app-argon-config]="feed:luci"
BINARY_SOURCE[luci-i18n-argon-config-zh-cn]="feed:luci"

# --- Docker ---
BINARY_SOURCE[docker]="feed:packages"
BINARY_SOURCE[dockerd]="feed:packages"
BINARY_SOURCE[containerd]="feed:packages"
BINARY_SOURCE[runc]="feed:packages"
BINARY_SOURCE[tini]="feed:packages"
BINARY_SOURCE[docker-compose]="feed:packages"
BINARY_SOURCE[luci-lib-docker]="feed:luci"
BINARY_SOURCE[luci-app-docker]="feed:luci"
BINARY_SOURCE[luci-i18n-docker-zh-cn]="feed:luci"
BINARY_SOURCE[luci-app-dockerman]="feed:luci"
BINARY_SOURCE[luci-i18n-dockerman-zh-cn]="feed:luci"

# ==========================================
# 声明式内核依赖映射 (用于 gh-bin 包或隐式依赖兜底)
# 格式: BINARY_KERNEL_DEPS[包名]="CONFIG_XXX CONFIG_YYY"
# ==========================================
declare -A BINARY_KERNEL_DEPS

# Docker 需要的内核模块（ipk 声明中已有部分，这里做强制兜底）
BINARY_KERNEL_DEPS[docker]="CONFIG_VETH CONFIG_NETFILTER_XT_MATCH_ADDRTYPE CONFIG_IP_NF_TARGET_MASQUERADE"

# OpenClash 等需要 TUN 模块 (如果是 gh-bin 引入)
# BINARY_KERNEL_DEPS[luci-app-openclash]="CONFIG_TUN"

# 其他 gh-bin 纯二进制程序
# BINARY_KERNEL_DEPS[包名]="CONFIG_XXX"

# --- 商店（暂无稳定 ipk 源，暂不包含） ---
# BINARY_SOURCE[luci-app-store]="feed:packages"

# ==================== BINARY 包清单（禁用编译，开机装 ipk） ====================
CONFIG_MANIFEST_BINARY=""

# --- 代理/VPN ---
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-app-openclash"

# --- DNS ---
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY smartdns"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-app-smartdns"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-smartdns-zh-cn"

# --- 实用工具 ---
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-diskman-zh-cn"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-filemanager-zh-cn"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-app-ttyd luci-i18n-ttyd-zh-cn"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY openssh-sftp-server"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-ddns-zh-cn ddns-scripts-aliyun ddns-scripts"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-acme-zh-cn luci-app-acme acme acme-acmesh acme-acmesh-dnsapi"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY socat"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY iperf3"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-irqbalance-zh-cn"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-i18n-upnp-zh-cn"
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY speedtest-go tcpdump"

# --- 主题 ---
CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"

# --- Docker（条件编译） ---
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY docker dockerd containerd runc tini docker-compose"
    CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-lib-docker luci-app-docker luci-i18n-docker-zh-cn"
    CONFIG_MANIFEST_BINARY="$CONFIG_MANIFEST_BINARY luci-app-dockerman luci-i18n-dockerman-zh-cn"
else
    CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE docker dockerd containerd runc tini docker-compose"
    CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE luci-lib-docker luci-app-docker luci-i18n-docker-zh-cn"
    CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE luci-app-dockerman luci-i18n-dockerman-zh-cn"
fi

# --- 商店 ---
# luci-app-store 暂移除，等稳定 ipk 源

# ==================== 源码编译包（只需显式启用 feed 中非默认的包） ====================
CONFIG_MANIFEST_SOURCE=""

# ==================== 排除包 ====================
CONFIG_MANIFEST_EXCLUDE="$CONFIG_MANIFEST_EXCLUDE luci-app-fchomo"

# ==================== 应用清单 ====================
# 注意：apply_manifest() 不在本文件中调用，由 diy-part2.sh 在 make defconfig 之后执行
# 这是为了确保 scripts/config --disable 不会被后续的 make defconfig 复活 BINARY 包

# ==========================================
# 强制 LuCI 配对声明 (防呆：防止装了核心包没装界面)
# 格式：核心包名。只要核心包在 BINARY 清单中，luci-app-核心包名 也必须在清单中。
# ==========================================
BINARY_LUCI_MANDATORY=(
    "smartdns"
    "docker"
    "ttyd"
    "acme"
    "upnp"
    # 如果后续新增带界面的包，在这里追加
)

# 导出 BINARY_PACKAGES（供 prepare-binary.sh 消费）
export BINARY_PACKAGES="$CONFIG_MANIFEST_BINARY"
