#!/bin/bash
# scripts/runtime-glibc32.sh — 32 位 glibc 运行时提取
# 由 diy-part2.sh source 调用，CWD = openwrt/
# 优先使用预构建 tarball（runtime/glibc32.tar.gz），不存在时从 GitHub runner 提取

GLIBC_TARBALL="${REPO_ROOT:-.}/runtime/glibc32.tar.gz"

if [ -f "$GLIBC_TARBALL" ]; then
    echo "Found pre-built glibc32 tarball, extracting..."
    tar -xzf "$GLIBC_TARBALL" -C files/
    if [ -f "files/lib/ld-linux.so.2" ]; then
        echo "  glibc32 tarball extracted successfully"
        return 0
    else
        echo "  WARNING: glibc32 tarball appears incomplete, falling back to extraction"
    fi
fi

echo "Extracting 32-bit glibc runtime from GitHub runner..."

GLIBC32_DEST="files/lib32/glibc"
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

    # ld-linux.so.2: 32 位动态链接器（ELF .interp 硬编码 /lib/ 路径）
    if copy32 "/lib/ld-linux.so.2" "files/lib/ld-linux.so.2" || \
       copy32 "$I386_LIB/ld-linux.so.2" "files/lib/ld-linux.so.2"; then
        echo "  ld-linux.so.2 OK"
    else
        echo "  FAIL: ld-linux.so.2 not found"
    fi

    # 核心库
    for lib in libc.so.6 libpthread.so.0 libm.so.6 libdl.so.2 librt.so.1 libutil.so.1 libresolv.so.2; do
        copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/" && echo "  $lib OK" || echo "  WARNING: $lib missing"
    done

    # NSS 库
    for lib in libnss_dns.so.2 libnss_files.so.2; do
        copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/" && echo "  $lib OK" || true
    done

    # GCC/C++ 运行时
    for lib in libgcc_s.so.1 libstdc++.so.6; do
        if copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/"; then
            echo "  $lib OK"
        else
            FOUND=$(find /usr/lib /lib -name "$lib" -type f 2>/dev/null | grep -E 'i386|i686|32' | head -1)
            if [ -n "$FOUND" ]; then
                cp -L "$FOUND" "$GLIBC32_DEST/"
                echo "  $lib OK (from $FOUND)"
            else
                echo "  WARNING: $lib not found"
            fi
        fi
    done

    # zlib
    copy32 "$I386_LIB/libz.so.1" "$GLIBC32_DEST/" && echo "  libz.so.1 OK" || true

    # OpenSSL
    for lib in libssl.so.3 libcrypto.so.3; do
        copy32 "$I386_LIB/$lib" "$GLIBC32_DEST/" && echo "  $lib OK" || true
    done

    echo "32-bit glibc runtime files (in /lib32/glibc/):"
    ls -la "$GLIBC32_DEST"/libc.so.6 "$GLIBC32_DEST"/libstdc++.so.6 2>/dev/null || true
fi
