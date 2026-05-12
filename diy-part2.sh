#!/bin/bash
# diy-part2.sh - 自定义配置 (在 .config 加载后、make defconfig 前运行)

# ============= 禁用 kenzo feed 中有问题的包（递归依赖）=============
# luci-app-fchomo 依赖自身导致 Kconfig 递归依赖警告
sed -i 's/.*CONFIG_PACKAGE_luci-app-fchomo.*/# CONFIG_PACKAGE_luci-app-fchomo is not set/' .config 2>/dev/null || true

# ============= 启用 IA32_EMULATION（32位应用支持）=============
KERNEL_CONFIG="target/linux/x86/config-6.6"
if [ -f "$KERNEL_CONFIG" ]; then
    if grep -q "^CONFIG_IA32_EMULATION=y$" "$KERNEL_CONFIG" 2>/dev/null; then
        echo "IA32_EMULATION already enabled in kernel config"
    elif grep -q "^# CONFIG_IA32_EMULATION is not set$" "$KERNEL_CONFIG" 2>/dev/null; then
        sed -i 's/^# CONFIG_IA32_EMULATION is not set$/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG"
        echo "IA32_EMULATION uncommented in kernel config"
    elif grep -q "CONFIG_IA32_EMULATION" "$KERNEL_CONFIG" 2>/dev/null; then
        sed -i 's/^.*CONFIG_IA32_EMULATION.*$/CONFIG_IA32_EMULATION=y/' "$KERNEL_CONFIG"
        echo "IA32_EMULATION fixed in kernel config"
    else
        echo "CONFIG_IA32_EMULATION=y" >> "$KERNEL_CONFIG"
        echo "IA32_EMULATION appended to kernel config"
    fi
else
    echo "WARNING: Kernel config not found at $KERNEL_CONFIG"
fi

# 补充内核新增选项，避免 syncconfig 交互式询问导致编译失败
# NET_9P_XEN 是 kernel 6.6.133 新增的选项，.config 中未覆盖
for opt in CONFIG_NET_9P_XEN; do
    if ! grep -q "^# $opt is not set$\|^$opt=" "$KERNEL_CONFIG" 2>/dev/null; then
        echo "# $opt is not set" >> "$KERNEL_CONFIG"
        echo "$opt disabled (kernel new option)"
    fi
done

# ============= 预置 32 位 musl 运行时 + 常用库 =============
#
# 方案说明:
#   内核 IA32_EMULATION 只负责 syscall 兼容，用户态库必须自己提供。
#   仅提供 ld-musl-i386.so.1 (libc) 是不够的——大部分 32 位程序还依赖
#   libgcc_s, libstdc++, libopenssl, libcurl, libz 等。
#
#   这里从 i386 rootfs 挂载提取多 library，放入 /lib32/。
#   32 位程序通过 /usr/bin/run-i386 包装脚本运行，它会用 --library-path
#   告诉 32 位 musl ld 优先从 /lib32/ 加载库，不会和 x86_64 的库冲突。
#   直接执行 32 位程序仍会触发内核加载 /lib/ld-musl-i386.so.1，但缺少
#   --library-path 时会去 /lib/ 查找 → 找到 64 位库 → 失败。
#   因此 32 位动态链接程序必须通过 run-i386 启动。
#   纯静态链接的 32 位程序可以直接执行。
#
#   注意: 不能用 /tmp（GitHub Actions runner 的 /tmp 是 tmpfs，仅 2-4GB）
#   rootfs 镜像解压后有 ~1.5GB，必须放工作目录。
# ================================================================

I386_ROOTFS_URL="https://downloads.immortalwrt.org/releases/24.10.6/targets/x86/generic/immortalwrt-24.10.6-x86-generic-generic-ext4-rootfs.img.gz"
WORKDIR="${GITHUB_WORKSPACE:-.}"
I386_TMP="$WORKDIR/i386-rootfs-tmp-$$"
I386_MOUNT="$WORKDIR/i386-mount-$$"
mkdir -p "$I386_TMP" "$I386_MOUNT" files/lib files/lib32

echo "Fetching 32-bit runtime from i386 rootfs..."

# Step 1: 下载
if ! wget -q --timeout=120 -O "$I386_TMP/rootfs.img.gz" "$I386_ROOTFS_URL" 2>/dev/null; then
    echo "FATAL: 下载 i386 rootfs 失败"
    echo "  URL: $I386_ROOTFS_URL"
    exit 1
fi

# Step 2: 解压
gunzip -f "$I386_TMP/rootfs.img.gz" 2>/dev/null || {
    echo "FATAL: 解压 i386 rootfs 失败"
    exit 1
}
ROOTFS_IMG="$I386_TMP/rootfs.img"

# Step 3: loop mount
sudo mount -o loop,ro "$ROOTFS_IMG" "$I386_MOUNT" 2>/dev/null
if ! mountpoint -q "$I386_MOUNT" 2>/dev/null; then
    echo "FATAL: loop mount i386 rootfs 失败"
    exit 1
fi
echo "Mounted i386 rootfs, extracting libraries..."

# Step 4: 提取 ld-musl-i386.so.1 (必须)
if [ ! -f "$I386_MOUNT/lib/libc.so" ]; then
    sudo umount "$I386_MOUNT"
    echo "FATAL: /lib/libc.so 在 i386 rootfs 中不存在"
    exit 1
fi
cp "$I386_MOUNT/lib/libc.so" files/lib/ld-musl-i386.so.1
chmod 755 files/lib/ld-musl-i386.so.1
echo "  ld-musl-i386.so.1 → /lib/"

# Step 5: 提取常用 32 位库 → /lib32/
# 优先从已挂载的 rootfs 搜索，缺失的从 i386 软件源下载 ipk 提取
#
# i386 包分布在 3 个 repo 目录下:
#   base/      → libopenssl3, zlib
#   packages/  → libcurl4
#   targets/   → libgcc1, libatomic1, libstdcpp6
I386_PKG_REPOS="
    https://downloads.immortalwrt.org/releases/24.10.6/packages/i386_pentium4/base
    https://downloads.immortalwrt.org/releases/24.10.6/packages/i386_pentium4/packages
    https://downloads.immortalwrt.org/releases/24.10.6/targets/x86/generic/packages
"
I386_PKG_CACHE="$WORKDIR/i386-pkg-cache-$$"
mkdir -p "$I386_PKG_CACHE"

# 确保异常退出时清理临时目录
trap "sudo umount '$I386_MOUNT' 2>/dev/null; rm -rf '$I386_TMP' '$I386_MOUNT' '$I386_PKG_CACHE'" EXIT

# 预下载所有 repo 索引（并行）
for repo_url in $I386_PKG_REPOS; do
    (
        repo_name=$(echo "$repo_url" | awk -F/ '{print $(NF-1)"/"$NF}')
        index_file="$I386_PKG_CACHE/${repo_name//\//_}.idx"
        wget -q --timeout=30 -O "${index_file}.gz" "$repo_url/Packages.gz" 2>/dev/null && \
            gunzip -f "${index_file}.gz" 2>/dev/null && \
            echo "  Index cached: $repo_name" || true
    ) &
done
wait

# 在所有索引中查找 ipk，返回完整下载 URL
find_ipk() {
    local pkg="$1"
    for repo_url in $I386_PKG_REPOS; do
        local repo_name=$(echo "$repo_url" | awk -F/ '{print $(NF-1)"/"$NF}')
        local idx="$I386_PKG_CACHE/${repo_name//\//_}.idx"
        [ -f "$idx" ] || continue
        local filename=$(awk -v pkg="$pkg" '
            /^Package:/{p=$2; f=""} /^Filename:/{f=$2}
            p==pkg && f{print f; exit}
        ' "$idx")
        if [ -n "$filename" ]; then
            echo "$repo_url/$filename"
            return 0
        fi
    done
    return 1
}

# 缓存 rootfs 文件列表，避免每个库都 find 遍历一次
ROOTFS_FILE_CACHE=$(find "$I386_MOUNT/lib" "$I386_MOUNT/usr/lib" -maxdepth 2 \
    \( -type f -o -type l \) 2>/dev/null)

extract_lib32() {
    local soname="$1"
    local ipk_pkg="$2"

    # 1) 从缓存的 rootfs 文件列表中搜索
    local src
    src=$(echo "$ROOTFS_FILE_CACHE" | grep -E "/${soname}(\.[0-9]+)*$" | head -1)
    if [ -n "$src" ] && [ -f "$src" ]; then
        cp -L "$src" "files/lib32/$soname"
        echo "  $soname → /lib32/ (from rootfs)"
        return 0
    fi

    # 2) 从 i386 ipk 下载提取（find_ipk 已直接返回完整 URL）
    local ipk_url=$(find_ipk "$ipk_pkg")
    if [ -n "$ipk_url" ]; then
        local ipk_file="$I386_PKG_CACHE/${ipk_pkg}.ipk"
        local ipk_dir="$I386_PKG_CACHE/${ipk_pkg}"
        if wget -q --timeout=60 -O "$ipk_file" "$ipk_url" 2>/dev/null; then
            mkdir -p "$ipk_dir"
            if tar -xzf "$ipk_file" -C "$ipk_dir" ./data.tar.gz 2>/dev/null && \
               tar -xzf "$ipk_dir/data.tar.gz" -C "$ipk_dir" 2>/dev/null; then
                local found
                found=$(find "$ipk_dir" -name "$soname" -o -name "${soname}.*" 2>/dev/null | head -1)
                if [ -n "$found" ] && [ -f "$found" ]; then
                    cp -L "$found" "files/lib32/$soname"
                    echo "  $soname → /lib32/ (from $ipk_pkg ipk)"
                    rm -rf "$ipk_dir" "$ipk_file"
                    return 0
                fi
            fi
            rm -rf "$ipk_dir" "$ipk_file"
        fi
    fi

    echo "  (缺失) $soname — 刷机后可用 opkg install $ipk_pkg 补装"
    return 1
}

# 按 soname → ipk 包名 正确映射（已通过仓库验证）
extract_lib32 "libgcc_s.so.1"     "libgcc1"
extract_lib32 "libatomic.so.1"    "libatomic1"
extract_lib32 "libstdc++.so.6"    "libstdcpp6"
extract_lib32 "libssl.so.3"      "libopenssl3"
extract_lib32 "libcrypto.so.3"   "libopenssl3"
extract_lib32 "libcurl.so.4"      "libcurl4"
extract_lib32 "libz.so.1"         "zlib"

rm -rf "$I386_PKG_CACHE"

sudo umount "$I386_MOUNT"
rm -rf "$I386_TMP" "$I386_MOUNT"

# Step 6: 创建 run-i386 包装脚本
mkdir -p files/usr/bin
cat > files/usr/bin/run-i386 << 'WRAPEOF'
#!/bin/sh
# run-i386 — 运行 32 位动态链接程序
# 自动识别 musl 或 glibc，设置正确的库搜索路径到 /lib32/
if [ $# -eq 0 ]; then
    echo "Usage: run-i386 <32-bit-binary> [args...]" >&2
    exit 1
fi
INTERP=$(readelf -l "$1" 2>/dev/null | awk '/Requesting program interpreter/{print $3}' | tr -d '[]')
case "$INTERP" in
    */ld-musl-i386.so.1)
        exec /lib/ld-musl-i386.so.1 --library-path /lib32:/usr/lib32 "$@" ;;
    */ld-linux.so.2)
        export LD_LIBRARY_PATH=/lib32:/usr/lib32${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        exec "$@" ;;
    *)
        echo "Unknown or missing 32-bit interpreter: ${INTERP:-none}" >&2
        exit 1 ;;
esac
WRAPEOF
chmod 755 files/usr/bin/run-i386

echo ""
echo "=== 32 位运行时就绪 ==="
ls -lh files/lib/ld-musl-i386.so.1
ls -lh files/lib32/ 2>/dev/null
echo "  run-i386 → /usr/bin/"
echo "======================="

# ============= 预置 32 位 glibc 运行时 =============
# 绝大多数预编译的 32 位 Linux 程序链接 glibc（非 musl）。
# 从 GitHub Actions runner (ubuntu-22.04) 提取 i386 glibc 运行时，
# libc6-dev-i386 / gcc-multilib 已由环境准备步骤安装。
echo "Installing 32-bit glibc runtime..."

GLIBC32_DEST="files/lib32"
mkdir -p "$GLIBC32_DEST" "files/lib"

# 定位 runner 上的 32 位库目录
I386_LIB=""
for d in /lib/i386-linux-gnu /usr/lib/i386-linux-gnu /usr/lib32 /lib32; do
    if [ -f "$d/libc.so.6" ] || [ -f "$d/libc.so" ]; then
        I386_LIB="$d"
        break
    fi
done

copy32() {
    local src="$1"
    local dst="$2"
    [ -f "$src" ] && cp -L "$src" "$dst" && return 0
    return 1
}

if [ -z "$I386_LIB" ]; then
    echo "WARNING: 32-bit glibc not found on runner. Only musl 32-bit supported."
else
    echo "Found 32-bit glibc at: $I386_LIB"

    # ld-linux.so.2 必须放 /lib/（ELF .interp 硬编码），其余放 /lib32/
    if copy32 "/lib/ld-linux.so.2" "files/lib/ld-linux.so.2" || \
       copy32 "$I386_LIB/ld-linux.so.2" "files/lib/ld-linux.so.2"; then
        echo "  ld-linux.so.2 → /lib/"
    else
        echo "  FAIL: ld-linux.so.2 not found"
    fi

    for lib in libc.so.6 libpthread.so.0 libm.so.6 libdl.so.2 librt.so.1 libutil.so.1 libresolv.so.2; do
        copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/" && echo "  $lib → /lib32/" || echo "  WARNING: $lib missing"
    done

    for lib in libnss_dns.so.2 libnss_files.so.2; do
        copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/" && echo "  $lib → /lib32/" || true
    done

    for lib in libgcc_s.so.1 libstdc++.so.6; do
        if copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/"; then
            echo "  $lib → /lib32/"
        else
            FOUND=$(find /usr/lib /lib -name "$lib" -type f 2>/dev/null | grep -E 'i386|i686|32' | head -1)
            if [ -n "$FOUND" ]; then
                cp -L "$FOUND" "$GLIBC32_DEST/"
                echo "  $lib → /lib32/ (from $FOUND)"
            else
                echo "  WARNING: $lib not found"
            fi
        fi
    done

    copy32 "$I386_LIB/libz.so.1" "$GLIBC32_DEST/" && echo "  libz.so.1 → /lib32/" || true

    for lib in libssl.so.3 libcrypto.so.3; do
        copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/" && echo "  $lib → /lib32/" || true
    done

    echo "32-bit glibc runtime files:"
    ls -la files/lib/ld-linux.so.2 "$GLIBC32_DEST"/libc.so.6 "$GLIBC32_DEST"/libstdc++.so.6 2>/dev/null || true
fi

# ============= Docker 开关 =============
DOCKER_PKGS="dockerd docker docker-compose luci-lib-docker luci-app-docker luci-app-dockerman"
if [ "${INCLUDE_DOCKER:-yes}" = "yes" ]; then
    echo "Enabling Docker packages..."
    action="=y"
else
    echo "Disabling Docker packages..."
    action=" is not set"
fi

sed_args=""
for pkg in $DOCKER_PKGS; do
    pkg_conf=$(echo "$pkg" | sed 's/-/_/g')
    sed_args="$sed_args -e s/.*CONFIG_PACKAGE_${pkg_conf}.*/CONFIG_PACKAGE_${pkg_conf}${action}/"
done
sed -i $sed_args .config

# ============= Rootfs 大小调整 =============
if [ -n "${ROOTFS_SIZE:-}" ] && [ "$ROOTFS_SIZE" != "4096" ]; then
    echo "Setting rootfs size to ${ROOTFS_SIZE} MB..."
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_SIZE}/" .config
fi

# ============= 第三方自定义软件包 =============
# diy-part2.sh 由 workflow 从 GITHUB_WORKSPACE 调用，CWD = openwrt/
# shell 脚本在仓库根目录的 shell/ 下
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CUSTOM_PACKAGES=""

if [ -f "$REPO_ROOT/shell/custom-packages.sh" ]; then
    . "$REPO_ROOT/shell/custom-packages.sh"
fi

# 处理 store .run 包（需在写入 .config 前完成 files/ 填充）
# 注意: files/ 已被 workflow 移动到 openwrt/files/，即当前目录下的 files/
if [ -n "$CUSTOM_PACKAGES" ] && echo "$CUSTOM_PACKAGES" | grep -q "luci-app-store"; then
    if [ -f "$REPO_ROOT/shell/prepare-store.sh" ]; then
        . "$REPO_ROOT/shell/prepare-store.sh"
        # files/ 相对于当前 CWD (openwrt/)
        prepare_store_packages "files" "$CUSTOM_PACKAGES"
        # store 包通过 files/ 直接植入 rootfs，不需要 CONFIG 条目
        CUSTOM_PACKAGES=$(echo "$CUSTOM_PACKAGES" | sed 's/luci-app-store//g' | xargs)
    fi
fi

# 将 CUSTOM_PACKAGES 写入 .config
if [ -n "$CUSTOM_PACKAGES" ]; then
    echo "=== 启用第三方软件包 ==="
    for pkg in $CUSTOM_PACKAGES; do
        # 处理排除项 (减号前缀)
        if echo "$pkg" | grep -q '^-'; then
            pkg_name=$(echo "$pkg" | sed 's/^-//')
            echo "  排除: $pkg_name"
            sed -i "s/.*CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/" .config 2>/dev/null || true
        else
            echo "  启用: $pkg"
            # 转换包名中的特殊字符为下划线
            pkg_conf=$(echo "$pkg" | sed 's/-/_/g')
            # 检查 .config 中是否已有此项
            if grep -q "CONFIG_PACKAGE_${pkg_conf}[= ]" .config 2>/dev/null; then
                sed -i "s/.*CONFIG_PACKAGE_${pkg_conf}.*/CONFIG_PACKAGE_${pkg_conf}=y/" .config
            else
                echo "CONFIG_PACKAGE_${pkg_conf}=y" >> .config
            fi
        fi
    done
    echo "=== 第三方包处理完毕 ==="
fi
