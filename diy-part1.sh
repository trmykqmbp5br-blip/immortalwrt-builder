#!/bin/bash
# diy-part1.sh - Custom feeds (runs before feeds update/install)

# 当前包选择无需第三方 feeds，所有包均来自 ImmortalWrt 官方源。
# 如需 PassWall / OpenClash 等第三方包，取消下面的注释：
# echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default
# echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default
