#!/bin/bash
# diy-part1.sh - 自定义软件源 (在 feeds update/install 前运行)

# ============= 生成 PROVIDES 虚拟包 =============
# 必须在 feeds update 之前生成，否则索引里没有依赖信息
. "$GITHUB_WORKSPACE/scripts/config-manifest.sh"
bash "$GITHUB_WORKSPACE/scripts/generate-provides.sh"
# 链接到 package/ 下，feeds 扫描时能发现
ln -sf "$GITHUB_WORKSPACE/package/custom-provides" package/custom-provides 2>/dev/null || true

# ============= 第三方 feeds =============
# kenzo: PassWall, SSR-Plus, OpenClash, MosDNS, TurboACC 等
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default

# small: 依赖包 (xray-core, sing-box, hysteria 等)
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default

# sirpdboy: 高级设置、分区扩容、酷猫主题等
# echo "src-git sirpdboy https://github.com/sirpdboy/sirpdboy-package.git;main" >> feeds.conf.default
