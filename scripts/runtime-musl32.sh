#!/bin/bash
# scripts/runtime-musl32.sh — 强依赖版
set -euo pipefail

TARBALL="runtime/musl32.tar.gz"
DEST_DIR="files"

if [ ! -f "$TARBALL" ]; then
    echo "❌ 致命错误: musl32 tarball 未找到: $TARBALL"
    echo "   生成方法: cd repo-root && bash scripts/build-runtime-tarballs.sh"
    echo "   musl 32-bit 支持是必需的，构建终止。"
    exit 1
fi

echo "==> 解压 musl 32-bit 运行时..."
tar xzf "$TARBALL" -C "$DEST_DIR"
echo "✅ musl 32-bit 运行时解压完成"
