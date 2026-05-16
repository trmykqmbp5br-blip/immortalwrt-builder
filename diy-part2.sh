#!/bin/bash
set -e
cd /workdir/openwrt

# 1. 下载 kconfig-tool 到 OpenWrt 的 scripts/ 下
wget -O scripts/kconfig-tool https://raw.githubusercontent.com/torvalds/linux/master/scripts/config
chmod +x scripts/kconfig-tool scripts/*.sh

# 2. 注入 32 位运行时库到 files/
for script in runtime-musl32.sh runtime-glibc32.sh; do
    if [ -f "$GITHUB_WORKSPACE/scripts/$script" ]; then
        bash "$GITHUB_WORKSPACE/scripts/$script"
    else
        echo "⚠️ $script not found, skipping."
    fi
done

# 3. 🚨 关键修复：写入目标平台种子配置
cat > .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
EOF

# 4. 生成标准 .config（基于种子扩展出完整配置）
make defconfig

# 5. 注入内核补丁与 Docker 内核依赖
bash "$GITHUB_WORKSPACE/scripts/kernel-config.sh"

# 5.5 注入内核编译期 olddefconfig 补丁
if [ -f "$GITHUB_WORKSPACE/scripts/kernel-config-patch.py" ]; then
    python3 "$GITHUB_WORKSPACE/scripts/kernel-config-patch.py" include/kernel-defaults.mk
else
    echo "⚠️ scripts/kernel-config-patch.py not found, skipping."
fi

# 6. 启用 CCACHE 强锁
./scripts/kconfig-tool --enable CONFIG_USE_CCACHE
./scripts/kconfig-tool --set-str CONFIG_CCACHE_DIR "/home/runner/.ccache"

# 7.（可选）强制启用需要源码编译的包
# ./scripts/kconfig-tool --enable CONFIG_PACKAGE_docker
# ./scripts/kconfig-tool --enable CONFIG_PACKAGE_dockerd

# 8. 设置 rootfs 大小
if [ -n "$ROOTFS_SIZE" ]; then
    ./scripts/kconfig-tool --set-val CONFIG_TARGET_ROOTFS_PARTSIZE "$ROOTFS_SIZE"
fi

# 9. 安全地解决新引入的内核依赖
make olddefconfig

echo "✅ diy-part2: Native config applied with 32-bit & Docker kernel support."
