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

# ============= 黑名单：过滤官方源码中已声明 PROVIDES 的包 =============
# 这些包编译时就提供了自己的 PROVIDES，重复声明会导致冲突
echo "  Scanning for PROVIDES in official packages..."
PROVIDES_BLACKLIST=""
for mk in package/feeds/*/*/Makefile feeds/*/*/Makefile; do
    [ -f "$mk" ] || continue
    provides_line=$(grep -E '^PROVIDES:=' "$mk" 2>/dev/null | head -1)
    [ -z "$provides_line" ] && continue
    provides_pkgs="${provides_line#PROVIDES:=}"
    for pkg in $provides_pkgs; do
        pkg="${pkg#+}"
        PROVIDES_BLACKLIST="$PROVIDES_BLACKLIST $pkg"
    done
done

# 去重并过滤
FILTERED_LIST=""
for pkg in $PROVIDES_LIST; do
    if echo " $PROVIDES_BLACKLIST " | grep -q " $pkg "; then
        echo "  [SKIP] $pkg (official package already PROVIDES this)"
    else
        FILTERED_LIST="$FILTERED_LIST $pkg"
    fi
done
PROVIDES_LIST="${FILTERED_LIST# }"

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
