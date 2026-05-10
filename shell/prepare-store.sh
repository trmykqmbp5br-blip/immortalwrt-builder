#!/bin/bash
# prepare-store.sh — 处理 wukongdaily/store 的 .run 自解压包
#
# 原理: .run 文件是自解压脚本，内含 ipk 文件。
#       提取 ipk 后解包 data 部分到 files/ 目录，固件编译时直接包入 rootfs。
#       适用于无源码 feed 的二进制包（如 istore）。
#
# 用法: source shell/prepare-store.sh && prepare_store_packages "files" "$CUSTOM_PACKAGES"

STORE_TMP="/tmp/store-repo-$$"

prepare_store_packages() {
    local FILES_DIR="${1:-files}"
    local WANTED="${2:-}"

    echo "=== 处理 store 第三方包 ==="

    [ -z "$WANTED" ] && { echo "无指定 store 包，跳过"; return 0; }

    echo "克隆 wukongdaily/store ..."
    git clone --depth=1 https://github.com/wukongdaily/store.git "$STORE_TMP" 2>/dev/null || {
        echo "WARNING: 无法克隆 store 仓库，跳过 store 包"
        return 0
    }

    mkdir -p "$FILES_DIR"

    # 遍历 x86 架构的 .run 文件
    for run_file in "$STORE_TMP/run/x86/"*.run; do
        [ -e "$run_file" ] || continue
        local fname=$(basename "$run_file" .run)

        # 检查是否在用户选择的包列表中
        local match=0
        for wanted_pkg in $WANTED; do
            # 匹配: 文件名包含包名(去除版本号)
            local pkg_base=$(echo "$wanted_pkg" | sed 's/^[+-]//')
            if echo "$fname" | grep -qi "$pkg_base"; then
                match=1
                break
            fi
        done

        [ "$match" -eq 0 ] && continue
        echo "  解压: $fname"

        local UNPACK_DIR=$(mktemp -d)
        sh "$run_file" --target "$UNPACK_DIR" --noexec 2>/dev/null

        find "$UNPACK_DIR" -name "*.ipk" | while read ipk; do
            local pkg_name=$(basename "$ipk" .ipk | sed 's/_[^_]*_[^_]*$//')
            echo "    安装: $pkg_name"

            local IPK_TMP=$(mktemp -d)
            (
                cd "$IPK_TMP"
                tar -xzf "$ipk" ./data.tar.gz 2>/dev/null || tar -xzf "$ipk" ./data.tar.xz 2>/dev/null || true
                if [ -f "./data.tar.gz" ]; then
                    tar -xzf "./data.tar.gz" -C "$FILES_DIR" 2>/dev/null
                elif [ -f "./data.tar.xz" ]; then
                    tar -xJf "./data.tar.xz" -C "$FILES_DIR" 2>/dev/null
                fi
            )
            rm -rf "$IPK_TMP"
        done
        rm -rf "$UNPACK_DIR"
    done

    rm -rf "$STORE_TMP"
    echo "=== store 包处理完成 ==="
}
