#!/bin/bash
set -e

# ==========================================
# P0 防御：检查关键环境变量
# ==========================================
: "${GITHUB_WORKSPACE:?❌ 错误：环境变量 GITHUB_WORKSPACE 未定义！请确保在 GitHub Actions 环境中运行，或手动 export 该变量。}"

# 如果有其他关键变量，也可以一并检查，例如 OPENWRT_ROOT（如果你是靠变量传递的）
# : "${OPENWRT_ROOT:?❌ 错误：OPENWRT_ROOT 未定义！}"

echo "✅ 环境变量检查通过，工作区: $GITHUB_WORKSPACE"

# ============= 预先注入 PROVIDES 虚拟包 =============
# 必须在 feeds update/install 之前，否则依赖解析找不到

# 1. 读取 BINARY_SOURCE 声明
source "$GITHUB_WORKSPACE/scripts/config-manifest.sh"

# 2. 动态生成 PROVIDES 虚拟包 Makefile
bash "$GITHUB_WORKSPACE/scripts/generate-provides.sh"

# 3. 链接到 openwrt 源码树
ln -sf "$GITHUB_WORKSPACE/package/custom-provides" "$OPENWRT_ROOT/package/custom-provides"

# ============= 第三方 feeds（必须在 feeds update 之前添加） =============
# kenzo: PassWall, SSR-Plus, OpenClash, MosDNS, TurboACC 等
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default
# small: 依赖包 (xray-core, sing-box, hysteria 等)
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default

# 4. 建立索引
./scripts/feeds update -a
./scripts/feeds install -a

# 5. 替换所有 BINARY 包的 Makefile 为 @BROKEN 空壳
#   之后 make defconfig 时 Kconfig 会自动设为 n，无需再用 apply_manifest 禁用
for pkg in $BINARY_PACKAGES_FLAT; do
  PKG_DIR=$(find package/feeds -type d -name "$pkg" 2>/dev/null | head -n 1)
  if [ -n "$PKG_DIR" ]; then
    cat > "$PKG_DIR/Makefile" << BROKENEOF
include \$(TOPDIR)/rules.mk
PKG_NAME:=$pkg
include \$(INCLUDE_DIR)/package.mk
define Package/$pkg
  TITLE:=$pkg (Binary Placeholder)
  DEPENDS:=@BROKEN
endef
define Package/$pkg/install
endef
\$(eval \$(call BuildPackage,$pkg))
BROKENEOF
    echo "  @BROKEN: $pkg"
  fi
done
