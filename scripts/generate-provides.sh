#!/bin/bash
# scripts/generate-provides.sh — 动态生成 custom-binary-provides Makefile
# 替代手动维护 PROVIDES 列表，由 diy-part2.sh 在 make defconfig 之前调用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 采集 BINARY 包列表
if [ -z "$CONFIG_MANIFEST_BINARY" ]; then
    if [ -f "$SCRIPT_DIR/config-manifest.sh" ]; then
        . "$SCRIPT_DIR/config-manifest.sh" 2>/dev/null || true
    fi
fi

PROVIDES_LIST="$CONFIG_MANIFEST_BINARY"
OUTPUT_DIR="package/custom-provides"
OUTPUT_FILE="$OUTPUT_DIR/Makefile"

mkdir -p "$OUTPUT_DIR"

echo "=== Generating custom-binary-provides Makefile ==="

cat > "$OUTPUT_FILE" << MAKEEOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=custom-binary-provides
PKG_VERSION:=1.0
PKG_RELEASE:=1

include \$(INCLUDE_DIR)/package.mk

define Package/custom-binary-provides
  SECTION:=utils
  CATEGORY:=Extra packages
  TITLE:=Virtual package providing all BINARY dependencies
  PROVIDES:=${PROVIDES_LIST}
endef

define Package/custom-binary-provides/install
	true
endef

\$(eval \$(call BuildPackage,custom-binary-provides))
MAKEEOF

echo "  PROVIDES: $PROVIDES_LIST"
echo "  Written: $OUTPUT_FILE"
