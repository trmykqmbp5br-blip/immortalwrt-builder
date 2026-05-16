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

# 4. 建立索引（此时扫描到的就是包含最新 PROVIDES 的 Makefile）
./scripts/feeds update -a
./scripts/feeds install -a

# ============= 第三方 feeds =============
# kenzo: PassWall, SSR-Plus, OpenClash, MosDNS, TurboACC 等
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default

# small: 依赖包 (xray-core, sing-box, hysteria 等)
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default

# sirpdboy: 高级设置、分区扩容、酷猫主题等
# echo "src-git sirpdboy https://github.com/sirpdboy/sirpdboy-package.git;main" >> feeds.conf.default
