#!/bin/bash
# scripts/docker-toggle.sh — Docker 包开关
# 由 diy-part2.sh source 调用，CWD = openwrt/
# Docker 已全部改为二进制 ipk 注入（见 shell/custom-packages.sh），
# 这里只负责：.config 里禁用 Docker 编译（防止源码编译 + 避免依赖断裂）
#
# 二进制注入由 shell/custom-packages.sh 根据 $INCLUDE_DOCKER 控制。

DOCKER_PKGS="dockerd docker docker-compose luci-lib-docker luci-app-docker luci-app-dockerman"

for pkg in $DOCKER_PKGS; do
    sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/# CONFIG_PACKAGE_${pkg} is not set/" .config 2>/dev/null || true
done

echo "Docker: 已禁用 .config 编译（走二进制注入），INCLUDE_DOCKER=${INCLUDE_DOCKER:-yes}"
