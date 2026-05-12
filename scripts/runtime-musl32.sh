#!/bin/bash
# scripts/runtime-musl32.sh — 32 位 musl 运行时提取
# 由 diy-part2.sh source 调用，CWD = openwrt/
# 优先使用预构建 tarball（runtime/musl32.tar.gz），不存在时从 i386 rootfs 提取

MUSL_TARBALL="${REPO_ROOT:-.}/runtime/musl32.tar.gz"

if [ -f "$MUSL_TARBALL" ]; then
    echo "Found pre-built musl32 tarball, extracting..."
    tar -xzf "$MUSL_TARBALL" -C files/
    if [ -f "files/lib/ld-musl-i386.so.1" ]; then
        echo "  musl32 tarball extracted successfully"
        ls -lh files/lib/ld-musl-i386.so.1
        return 0
    else
        echo "  WARNING: musl32 tarball appears incomplete, falling back to extraction"
    fi
fi

echo "Extracting 32-bit musl runtime from i386 rootfs..."

I386_ROOTFS_URL="https://downloads.immortalwrt.org/releases/24.10.6/targets/x86/generic/immortalwrt-24.10.6-x86-generic-generic-ext4-rootfs.img.gz"
WORKDIR="${GITHUB_WORKSPACE:-..}"
I386_TMP="$WORKDIR/i386-rootfs-tmp-$$"
I386_MOUNT="$WORKDIR/i386-mount-$$"
mkdir -p "$I386_TMP" "$I386_MOUNT" files/lib files/lib32

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

# Step 4: 提取 ld-musl-i386.so.1
if [ ! -f "$I386_MOUNT/lib/libc.so" ]; then
    sudo umount "$I386_MOUNT"
    echo "FATAL: /lib/libc.so 在 i386 rootfs 中不存在"
    exit 1
fi
cp "$I386_MOUNT/lib/libc.so" files/lib/ld-musl-i386.so.1
chmod 755 files/lib/ld-musl-i386.so.1
echo "  ld-musl-i386.so.1 → /lib/"

# Step 5: 提取常用 32 位库 → /lib32/
I386_PKG_REPOS="
    https://downloads.immortalwrt.org/releases/24.10.6/packages/i386_pentium4/base
    https://downloads.immortalwrt.org/releases/24.10.6/packages/i386_pentium4/packages
    https://downloads.immortalwrt.org/releases/24.10.6/targets/x86/generic/packages
"
I386_PKG_CACHE="$WORKDIR/i386-pkg-cache-$$"
mkdir -p "$I386_PKG_CACHE"

for repo_url in $I386_PKG_REPOS; do
    repo_name=$(echo "$repo_url" | awk -F/ '{print $(NF-1)"/"$NF}')
    index_file="$I386_PKG_CACHE/${repo_name//\//_}.idx"
    wget -q --timeout=30 -O "${index_file}.gz" "$repo_url/Packages.gz" 2>/dev/null && \
        gunzip -f "${index_file}.gz" 2>/dev/null && \
        echo "  Index cached: $repo_name" || true
done

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

extract_lib32() {
    local soname="$1"
    local ipk_pkg="$2"

    # 1) 在 rootfs 中搜索
    local src
    src=$(find "$I386_MOUNT/lib" "$I386_MOUNT/usr/lib" -maxdepth 2 \
        \( -name "$soname" -o -name "${soname}.*" \) \( -type f -o -type l \) 2>/dev/null | head -1)
    if [ -n "$src" ] && [ -f "$src" ]; then
        cp -L "$src" "files/lib32/$soname"
        echo "  $soname → /lib32/ (from rootfs)"
        return 0
    fi

    # 2) 从 i386 ipk 下载提取
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

echo ""
echo "=== 32 位 musl 运行时就绪 ==="
ls -lh files/lib/ld-musl-i386.so.1
ls -lh files/lib32/ 2>/dev/null
echo "=============================="
