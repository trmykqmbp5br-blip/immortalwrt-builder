#!/bin/bash
# scripts/runtime-musl32.sh — 32 位 musl 运行时提取
# 由 diy-part2.sh source 调用，CWD = openwrt/
# 从 runtime/musl32.tar.gz 解压预构建 32 位 musl 库到 files/

MUSL_TARBALL="${REPO_ROOT:-.}/runtime/musl32.tar.gz"

if [ -f "$MUSL_TARBALL" ]; then
    echo "Found pre-built musl32 tarball, extracting..."
    tar -xzf "$MUSL_TARBALL" -C files/
    if [ -f "files/lib/ld-musl-i386.so.1" ]; then
        echo "  musl32 tarball extracted successfully"
        ls -lh files/lib/ld-musl-i386.so.1
        return 0
    else
        echo "  WARNING: musl32 tarball appears incomplete"
    fi
fi

echo "WARNING: musl32 tarball not found. musl 32-bit support will be unavailable."
echo "To generate: cd repo-root && bash scripts/build-runtime-tarballs.sh"
