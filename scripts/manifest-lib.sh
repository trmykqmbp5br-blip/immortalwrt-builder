#!/bin/bash
# scripts/manifest-lib.sh — 统一包配置机制层
# 由 diy-part2.sh 在 openwrt/ 目录下 source

# ================================================================
# apply_manifest — 根据三份列表统一写入 .config
# 用法: apply_manifest "binary_pkgs" "exclude_pkgs" "source_pkgs"
# 使用 Linux kernel 的 scripts/config（重命名为 kconfig-tool，避免与 OpenWrt 的 scripts/config/ 目录冲突）
#
# 调用时机：必须在 make defconfig 之后，且不再执行第二次 make defconfig
# ================================================================
apply_manifest() {
    local binary_list="$1"
    local exclude_list="$2"
    local source_list="$3"
    local pkg

    # 二进制 ipk 包：禁用 .config
    for pkg in $binary_list; do
        ./scripts/kconfig-tool --disable "CONFIG_PACKAGE_${pkg}" 2>/dev/null || true
    done

    # 排除包：禁用 .config
    for pkg in $exclude_list; do
        ./scripts/kconfig-tool --disable "CONFIG_PACKAGE_${pkg}" 2>/dev/null || true
    done

    # 源码编译包：启用 .config
    for pkg in $source_list; do
        ./scripts/kconfig-tool --enable "CONFIG_PACKAGE_${pkg}" 2>/dev/null || true
    done

    # 启用 PROVIDES 虚拟包（编译空包，接管所有 BINARY 包的依赖请求）
    ./scripts/kconfig-tool --enable "CONFIG_PACKAGE_custom-binary-provides" 2>/dev/null || true
}
