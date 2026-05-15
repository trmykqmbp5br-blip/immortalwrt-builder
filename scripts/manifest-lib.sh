#!/bin/bash
# scripts/manifest-lib.sh — 统一包配置机制层
# 由 diy-part2.sh 在 openwrt/ 目录下 source

# ================================================================
# apply_manifest — 根据三份列表统一写入 .config
# 用法: apply_manifest "binary_pkgs" "exclude_pkgs" "source_pkgs"
# binary — 禁用 .config，不编译；feed/GitHub 来源的 ipk 开机装
# exclude — 禁用 .config，不编译不安装
# source — 启用 .config，正常编译
# ================================================================
apply_manifest() {
    local binary_list="$1"
    local exclude_list="$2"
    local source_list="$3"
    local pkg

    # 二进制 ipk 包：.config 禁用
    for pkg in $binary_list; do
        sed -i "/^CONFIG_PACKAGE_${pkg}=[ym]$/s/=.*/=n/" .config 2>/dev/null || true
        sed -i "/^# CONFIG_PACKAGE_${pkg} is not set$/d" .config 2>/dev/null || true
        echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
    done

    # 排除包：.config 禁用
    for pkg in $exclude_list; do
        sed -i "/^CONFIG_PACKAGE_${pkg}=[ym]$/s/=.*/=n/" .config 2>/dev/null || true
        sed -i "/^# CONFIG_PACKAGE_${pkg} is not set$/d" .config 2>/dev/null || true
        echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
    done

    # 源码编译包：.config 启用
    for pkg in $source_list; do
        sed -i "/^CONFIG_PACKAGE_${pkg}=n$/s/=n/=y/" .config 2>/dev/null || true
        if ! grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config 2>/dev/null; then
            sed -i "/^# CONFIG_PACKAGE_${pkg} is not set$/d" .config 2>/dev/null || true
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        fi
    done
}
