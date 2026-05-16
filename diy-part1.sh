#!/bin/bash
set -e

cd /workdir/openwrt

# 1. 添加必要的第三方 feeds (如需从源码编译特定第三方包，在此添加源)
# 若只编译官方包，此段可删
# cat >> feeds.conf.default <<EOF
# src-git kenzo https://github.com/kenzok8/openwrt-packages
# EOF

# 2. 标准的 feeds 更新与安装 (不再有任何篡改)
./scripts/feeds update -a
./scripts/feeds install -a

echo "✅ diy-part1: Feeds installed natively."
