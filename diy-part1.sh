#!/bin/bash
# diy-part1.sh - Custom feeds (runs before feeds update/install)

# Add third-party feeds for PassWall, etc.
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages.git;master" >> feeds.conf.default
echo "src-git small https://github.com/kenzok8/small.git;master" >> feeds.conf.default
