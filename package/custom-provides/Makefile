include $(TOPDIR)/rules.mk

PKG_NAME:=custom-binary-provides
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/custom-binary-provides
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=Virtual package providing all BINARY dependencies
  PROVIDES:=luci-app-openclash smartdns luci-app-smartdns luci-i18n-smartdns-zh-cn luci-i18n-diskman-zh-cn luci-i18n-filemanager-zh-cn luci-app-ttyd luci-i18n-ttyd-zh-cn openssh-sftp-server luci-i18n-ddns-zh-cn ddns-scripts-aliyun ddns-scripts luci-i18n-acme-zh-cn luci-app-acme acme acme-acmesh acme-acmesh-dnsapi socat iperf3 luci-i18n-irqbalance-zh-cn luci-i18n-upnp-zh-cn speedtest-go tcpdump luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn docker dockerd containerd runc tini docker-compose luci-lib-docker luci-app-docker luci-i18n-docker-zh-cn luci-app-dockerman luci-i18n-dockerman-zh-cn
endef

define Package/custom-binary-provides/install
	true
endef

$(eval $(call BuildPackage,custom-binary-provides))
