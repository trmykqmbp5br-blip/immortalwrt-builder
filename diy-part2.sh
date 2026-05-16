#!/bin/bash
set -e

cd /workdir/openwrt

# 1. 下载 kconfig-tool
wget -O scripts/kconfig-tool https://raw.githubusercontent.com/torvalds/linux/master/scripts/config
chmod +x scripts/kconfig-tool scripts/*.sh

# 2. 注入 32 位运行时库到 files/
bash scripts/runtime-musl32.sh
bash scripts/runtime-glibc32.sh

# 3. 🚨 先生成标准 .config（必须有这一步，否则 .config 不存在）
make defconfig

# 4. 注入内核补丁与 Docker 内核依赖（此时操作已存在的 .config 才有效）
bash scripts/kernel-config.sh

# 5. 启用 CCACHE 强锁
./scripts/kconfig-tool --enable CONFIG_CCACHE
./scripts/kconfig-tool --set-str CONFIG_CCACHE_DIR "/home/runner/.ccache"

# 6. (可选) 强制启用需要源码编译的包
# 例如：如果需要编译 docker-ce 源码包，在此强制启用
# ./scripts/kconfig-tool --enable CONFIG_PACKAGE_docker
# ./scripts/kconfig-tool --enable CONFIG_PACKAGE_dockerd

# 7. 安全地解决新引入的内核依赖 (此时执行是安全的，不会再复活被禁用的包)
make olddefconfig

echo "✅ diy-part2: Native config applied with 32-bit & Docker kernel support."
