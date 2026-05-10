#!/bin/bash
# diy-part1.sh - Custom feeds (runs before feeds update/install)

# Add third-party feeds for PassWall, etc.
echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> feeds.conf.default
echo "src-git passwall_luci https://github.com/xiaorouji/openwrt-passwall.git;main" >> feeds.conf.default
echo "src-git openclash https://github.com/vernesong/OpenClash.git;dev" >> feeds.conf.default
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default
