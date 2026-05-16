# scripts/binary-packages.sh — BINARY 包扁平列表
# 被 config-manifest.sh 和 diy-part2.sh 共同 source
# 用于生成 PROVIDES 虚拟包 + 导出 BINARY_PACKAGES
# 维护位置：config-manifest.sh 的 CONFIG_MANIFEST_BINARY 累积

# 扁平列表（不含条件分支如 Docker，COPY 自 CONFIG_MANIFEST_BINARY 最终值）
BINARY_PACKAGES_FLAT="luci-app-openclash smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn luci-i18n-diskman-zh-cn luci-i18n-filemanager-zh-cn luci-app-ttyd luci-i18n-ttyd-zh-cn openssh-sftp-server luci-i18n-ddns-zh-cn ddns-scripts-aliyun ddns-scripts luci-i18n-acme-zh-cn luci-app-acme acme acme-acmesh acme-acmesh-dnsapi socat iperf3 luci-i18n-irqbalance-zh-cn luci-i18n-upnp-zh-cn speedtest-go tcpdump luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn docker dockerd containerd runc tini docker-compose luci-lib-docker luci-i18n-docker-zh-cn luci-app-dockerman luci-i18n-dockerman-zh-cn"
