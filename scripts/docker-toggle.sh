#!/bin/bash
# scripts/docker-toggle.sh — Docker 包开关
# 由 diy-part2.sh source 调用，CWD = openwrt/
# 根据 $INCLUDE_DOCKER 环境变量启用/禁用 Docker 包

if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    echo "Enabling Docker packages..."
    sed -i 's/.*CONFIG_PACKAGE_dockerd.*/CONFIG_PACKAGE_dockerd=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker.*/CONFIG_PACKAGE_docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker-compose.*/CONFIG_PACKAGE_docker-compose=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-lib-docker.*/CONFIG_PACKAGE_luci-lib-docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-docker.*/CONFIG_PACKAGE_luci-app-docker=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-dockerman.*/CONFIG_PACKAGE_luci-app-dockerman=y/' .config
    # iptables-nft 必须 =y（Docker 依赖）
    sed -i 's/.*CONFIG_PACKAGE_iptables-nft.*/CONFIG_PACKAGE_iptables-nft=y/' .config
    sed -i 's/.*CONFIG_PACKAGE_ip6tables-nft.*/CONFIG_PACKAGE_ip6tables-nft=y/' .config
else
    echo "Disabling Docker packages..."
    sed -i 's/.*CONFIG_PACKAGE_dockerd.*/# CONFIG_PACKAGE_dockerd is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker .*/# CONFIG_PACKAGE_docker is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_docker-compose.*/# CONFIG_PACKAGE_docker-compose is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-lib-docker.*/# CONFIG_PACKAGE_luci-lib-docker is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-docker.*/# CONFIG_PACKAGE_luci-app-docker is not set/' .config
    sed -i 's/.*CONFIG_PACKAGE_luci-app-dockerman.*/# CONFIG_PACKAGE_luci-app-dockerman is not set/' .config
fi
