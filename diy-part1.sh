#!/bin/bash
# diy-part1.sh - 自定义软件源 (在 feeds update/install 前运行)

# ============= 第三方 feeds =============
# kenzo: PassWall, SSR-Plus, OpenClash, MosDNS, TurboACC 等
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default

# small: 依赖包 (xray-core, sing-box, hysteria 等)
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default

# sirpdboy: 高级设置、分区扩容、酷猫主题、luci-app-argon-config 等
echo "src-git sirpdboy https://github.com/sirpdboy/sirpdboy-package.git;main" >> feeds.conf.default

# animegasan: luci-app-alpha-config (luci-theme-alpha 依赖)
echo "src-git animegasan https://github.com/animegasan/luci-app-alpha-config.git;master" >> feeds.conf.default
