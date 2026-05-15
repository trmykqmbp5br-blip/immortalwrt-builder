include $(TOPDIR)/rules.mk

PKG_NAME:=custom-binary-provides
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/custom-binary-provides
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=Virtual package providing all BINARY dependencies
  PROVIDES:=
endef

define Package/custom-binary-provides/install
	true
endef

$(eval $(call BuildPackage,custom-binary-provides))
