#!/bin/sh
# 99-custom.sh — ImmortalWrt 首次启动脚本
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# ============= 读取 PPPoE 配置（由 GitHub Actions 构建时生成）=============
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Using DHCP for WAN." >>$LOGFILE
    ENABLE_PPPOE="no"
else
    . "$SETTINGS_FILE"
    echo "PPPoE settings loaded: enable_pppoe=$enable_pppoe" >>$LOGFILE
fi

# ============= 获取所有物理接口 =============
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')
count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames (count=$count)" >>$LOGFILE

# ============= 根据板子型号映射 WAN 和 LAN 接口 =============
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "Using $board_name mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>$LOGFILE
        ;;
    *)
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>$LOGFILE
        ;;
esac

# ============= 主机名映射（解决安卓原生 TV 无法联网）=============
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# ============= 网络配置 =============
if [ "$count" -eq 1 ]; then
    # 单网口模式：DHCP 自动获取
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network

    # 单网口必须开放 WAN 防火墙才能访问 WebUI（VM 场景）
    uci set firewall.@zone[1].input='ACCEPT'
    echo "Single-NIC mode: WAN firewall set to ACCEPT for WebUI access" >>$LOGFILE

elif [ "$count" -gt 1 ]; then
    # ===== 多网口模式 =====
    # --- WAN 口 ---
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"

    # --- WAN6 ---
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"

    # --- PPPoE 配置（仅当 enable_pppoe=yes 时）---
    if [ "$enable_pppoe" = "yes" ]; then
        if [ -n "$pppoe_wan_account" ] && [ -n "$pppoe_wan_password" ]; then
            echo "Configuring WAN PPPoE..." >>$LOGFILE
            uci set network.wan.proto='pppoe'
            uci set network.wan.username="$pppoe_wan_account"
            uci set network.wan.password="$pppoe_wan_password"
            uci set network.wan.peerdns='1'
            uci set network.wan.auto='1'
            uci set network.wan.ipv6='auto'
            uci set network.wan.norelease='1'
            uci set network.wan.metric='1'
            uci set network.wan6.proto='none'
        else
            echo "PPPoE enabled but account/password missing. Falling back to DHCP." >>$LOGFILE
            uci set network.wan.proto='dhcp'
            uci set network.wan6.proto='dhcpv6'
        fi
    else
        uci set network.wan.proto='dhcp'
        uci set network.wan6.proto='dhcpv6'
    fi

    # --- 更新 br-lan 端口 ---
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error: cannot find device 'br-lan'." >>$LOGFILE
    else
        uci -q delete "network.$section.ports"
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # --- LAN 静态 IP ---
    uci set network.lan.proto='static'
    uci set network.lan.netmask='255.255.255.0'
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "Custom router IP: $CUSTOM_IP" >>$LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "Default router IP: 192.168.100.1" >>$LOGFILE
    fi

    # --- WAN 防火墙：多网口默认 DENY（安全优先）---
    echo "Multi-NIC mode: WAN firewall remains at default (REJECT)" >>$LOGFILE

    uci commit network

    # ============= 第二 WAN (wanb) 配置 =============
    # 当有 >1 物理网口时启用双 WAN
    wanb_ifname=$(echo "$ifnames" | awk '{print $2}')
    if [ -n "$wanb_ifname" ]; then
        echo "Configuring second WAN (wanb) on $wanb_ifname" >>$LOGFILE

        uci set network.wanb=interface
        uci set network.wanb.device="$wanb_ifname"

        if [ "$enable_pppoe" = "yes" ] && [ -n "$pppoe_wanb_account" ] && [ -n "$pppoe_wanb_password" ]; then
            echo "Configuring WANB PPPoE..." >>$LOGFILE
            uci set network.wanb.proto='pppoe'
            uci set network.wanb.username="$pppoe_wanb_account"
            uci set network.wanb.password="$pppoe_wanb_password"
            uci set network.wanb.ipv6='auto'
            uci set network.wanb.norelease='1'
            uci set network.wanb.metric='1'
            uci set network.wanb_6=interface
            uci set network.wanb_6.device="$wanb_ifname"
            uci set network.wanb_6.proto='none'
        else
            echo "WANB using DHCP" >>$LOGFILE
            uci set network.wanb.proto='dhcp'
            uci set network.wanb_6=interface
            uci set network.wanb_6.device="$wanb_ifname"
            uci set network.wanb_6.proto='dhcpv6'
        fi

        # 防火墙 zone 添加 wanb
        uci add_list firewall.@zone[-1].network='wanb'
        uci add_list firewall.@zone[-1].network='wanb_6'

        uci commit network
        uci commit firewall

        # ============= mwan3 负载均衡配置 =============
        if command -v mwan3 >/dev/null 2>&1; then
            echo "mwan3 detected, configuring load balancing..." >>$LOGFILE

            uci set mwan3.wan=interface
            uci set mwan3.wan.enabled='1'
            uci set mwan3.wan.family='ipv4'
            uci set mwan3.wan.reliability='2'
            uci add_list mwan3.wan.track_ip='223.5.5.5'
            uci add_list mwan3.wan.track_ip='119.29.29.29'
            uci set mwan3.wan.flush_conntrack='disconnected'

            uci set mwan3.wanb=interface
            uci set mwan3.wanb.enabled='1'
            uci set mwan3.wanb.family='ipv4'
            uci set mwan3.wanb.reliability='2'
            uci add_list mwan3.wanb.track_ip='223.5.5.5'
            uci add_list mwan3.wanb.track_ip='119.29.29.29'
            uci set mwan3.wanb.flush_conntrack='disconnected'

            uci set mwan3.wan_6=interface
            uci set mwan3.wan_6.enabled='1'
            uci set mwan3.wan_6.family='ipv6'
            uci set mwan3.wan_6.reliability='0'

            uci set mwan3.wanb_6=interface
            uci set mwan3.wanb_6.enabled='1'
            uci set mwan3.wanb_6.family='ipv6'
            uci set mwan3.wanb_6.reliability='0'

            uci set mwan3.wan_v4=member
            uci set mwan3.wan_v4.interface='wan'
            uci set mwan3.wan_v4.metric='1'
            uci set mwan3.wan_v4.weight='1'

            uci set mwan3.wanb_v4=member
            uci set mwan3.wanb_v4.interface='wanb'
            uci set mwan3.wanb_v4.metric='1'
            uci set mwan3.wanb_v4.weight='1'

            uci set mwan3.wan_v6=member
            uci set mwan3.wan_v6.interface='wan_6'
            uci set mwan3.wan_v6.metric='1'
            uci set mwan3.wan_v6.weight='1'

            uci set mwan3.wanb_v6=member
            uci set mwan3.wanb_v6.interface='wanb_6'
            uci set mwan3.wanb_v6.metric='1'
            uci set mwan3.wanb_v6.weight='1'

            uci set mwan3.balanced=policy
            uci add_list mwan3.balanced.use_member='wan_v4'
            uci add_list mwan3.balanced.use_member='wanb_v4'
            uci add_list mwan3.balanced.use_member='wan_v6'
            uci add_list mwan3.balanced.use_member='wanb_v6'
            uci set mwan3.balanced.last_resort='unreachable'

            uci set mwan3.wan_only=policy
            uci add_list mwan3.wan_only.use_member='wan_v4'
            uci add_list mwan3.wan_only.use_member='wan_v6'
            uci set mwan3.wan_only.last_resort='unreachable'

            uci set mwan3.wanb_only=policy
            uci add_list mwan3.wanb_only.use_member='wanb_v4'
            uci add_list mwan3.wanb_only.use_member='wanb_v6'
            uci set mwan3.wanb_only.last_resort='unreachable'

            uci set mwan3.https=rule
            uci set mwan3.https.dest_port='443'
            uci set mwan3.https.proto='tcp'
            uci set mwan3.https.use_policy='balanced'

            uci set mwan3.default_v4=rule
            uci set mwan3.default_v4.dest_ip='0.0.0.0/0'
            uci set mwan3.default_v4.family='ipv4'
            uci set mwan3.default_v4.use_policy='balanced'

            uci set mwan3.default_v6=rule
            uci set mwan3.default_v6.dest_ip='::/0'
            uci set mwan3.default_v6.family='ipv6'
            uci set mwan3.default_v6.use_policy='balanced'

            uci commit mwan3
            echo "mwan3 load balancing configured" >>$LOGFILE
        fi
    fi
fi

# ============= Docker 防火墙规则 =============
if command -v dockerd >/dev/null 2>&1; then
    echo "Docker detected, loading kernel modules..." >>$LOGFILE
    modprobe br-netfilter 2>/dev/null && echo "br-netfilter loaded" >>$LOGFILE
    modprobe veth 2>/dev/null && echo "veth loaded" >>$LOGFILE
    sysctl -w net.bridge.bridge-nf-call-iptables=1 >>$LOGFILE 2>&1
    grep -q 'bridge-nf-call-iptables' /etc/sysctl.conf 2>/dev/null || \
        echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.conf

    echo "Docker detected, configuring firewall rules..." >>$LOGFILE
    FW_FILE="/etc/config/firewall"

    uci delete firewall.docker

    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall

    cat <<'FWEOF' >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
FWEOF

else
    echo "Docker not detected, skipping firewall configuration." >>$LOGFILE
fi

# ============= 通用设置 =============
# 所有网口可访问 ttyd 网页终端
uci delete ttyd.@ttyd[0].interface

# 所有网口可 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 修复 luci-app-advancedplus 的 zsh 调用报错
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
fi

echo "99-custom.sh completed at $(date)" >>$LOGFILE
exit 0
