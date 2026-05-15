#!/bin/bash
# diy-part1.sh - 自定义软件源 (在 feeds update/install 前运行)

# ============= 第三方 feeds =============
# kenzo: PassWall, SSR-Plus, OpenClash, MosDNS, TurboACC 等
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default

# small: 依赖包 (xray-core, sing-box, hysteria 等)
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default

# sirpdboy: 高级设置、分区扩容、酷猫主题等
# echo "src-git sirpdboy https://github.com/sirpdboy/sirpdboy-package.git;main" >> feeds.conf.default

# ============= 链接 PROVIDES 虚拟包 =============
# 空包，PROVIDES 所有 BINARY 包，编译期依赖系统认为这些包已存在
ln -sf "${GITHUB_WORKSPACE}/package/custom-provides" "package/custom-provides" 2>/dev/null || true
