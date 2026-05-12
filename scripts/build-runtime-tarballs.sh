#!/bin/bash
# scripts/build-runtime-tarballs.sh — 从已提取的 files/ 创建运行时 tarball
# 在成功构建后运行：bash scripts/build-runtime-tarballs.sh
# 生成的 tarball 存入 runtime/，后续构建将使用它们跳过在线提取

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$REPO_ROOT/runtime"

# 切换到 openwrt/ 目录（构建时的 CWD）
if [ -d "$REPO_ROOT/openwrt" ]; then
    cd "$REPO_ROOT/openwrt"
elif [ -d "$REPO_ROOT/files" ]; then
    cd "$REPO_ROOT"
else
    echo "ERROR: 请在构建目录（openwrt/）或仓库根目录运行"
    exit 1
fi

# musl 32 位 tarball
if [ -f "files/lib/ld-musl-i386.so.1" ]; then
    echo "Creating musl32.tar.gz..."
    tar -czf "$REPO_ROOT/runtime/musl32.tar.gz" \
        files/lib/ld-musl-i386.so.1 \
        files/lib32/libgcc_s.so.1 \
        files/lib32/libatomic.so.1 \
        files/lib32/libstdc++.so.6 \
        files/lib32/libssl.so.3 \
        files/lib32/libcrypto.so.3 \
        files/lib32/libcurl.so.4 \
        files/lib32/libz.so.1
    echo "  musl32.tar.gz created ($(du -h "$REPO_ROOT/runtime/musl32.tar.gz" | cut -f1))"
else
    echo "  SKIP: musl 32-bit runtime not found in files/"
fi

# glibc 32 位 tarball
if [ -f "files/lib/ld-linux.so.2" ]; then
    echo "Creating glibc32.tar.gz..."
    tar -czf "$REPO_ROOT/runtime/glibc32.tar.gz" \
        files/lib/ld-linux.so.2 \
        files/lib32/glibc/
    echo "  glibc32.tar.gz created ($(du -h "$REPO_ROOT/runtime/glibc32.tar.gz" | cut -f1))"
else
    echo "  SKIP: glibc 32-bit runtime not found in files/"
fi

echo "Done. Tarballs saved to $REPO_ROOT/runtime/"
ls -lh "$REPO_ROOT/runtime/"
