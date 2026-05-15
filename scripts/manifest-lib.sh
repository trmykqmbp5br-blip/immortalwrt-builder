#!/bin/bash
# scripts/manifest-lib.sh — 统一包配置机制层
# 由 diy-part2.sh 在 openwrt/ 目录下 source

# ================================================================
# apply_manifest — 根据三份列表统一写入 .config
# 用法: apply_manifest "binary_pkgs" "exclude_pkgs" "source_pkgs"
# binary — 非 feed 包的 ipk，禁用 .config 避免 make 报错
# exclude — 禁用 .config，不编译不注入
# source — 启用 .config，正常编译
# ================================================================
apply_manifest() {
    local binary_list="$1"
    local exclude_list="$2"
    local source_list="$3"
    local pkg

    # 二进制 ipk 包（非 feed）：.config 禁用，不走源码编译
    for pkg in $binary_list; do
        sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/# CONFIG_PACKAGE_${pkg} is not set/" .config 2>/dev/null || true
    done

    # 排除包：.config 禁用
    for pkg in $exclude_list; do
        sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/# CONFIG_PACKAGE_${pkg} is not set/" .config 2>/dev/null || true
    done

    # 源码编译包：.config 启用
    for pkg in $source_list; do
        if grep -q "CONFIG_PACKAGE_${pkg}[= ]" .config 2>/dev/null; then
            sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/CONFIG_PACKAGE_${pkg}=y/" .config
        else
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        fi
    done
}
