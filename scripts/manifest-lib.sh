#!/bin/bash
# scripts/manifest-lib.sh — 统一包配置机制层
# 纯函数库，零策略（不包含任何包名）
# 策略写在 config-manifest.sh（声明包清单），
# 下载+清单生成写在 prepare-binary.sh。
#
# 由 diy-part2.sh 在 openwrt/ 目录下 source

# ================================================================
# apply_manifest — 根据三份列表统一写入 .config
# 用法: apply_manifest "binary_pkgs" "exclude_pkgs" "source_pkgs"
# 三种条目都是用原始包名（如 luci-app-openclash），
# 函数内部自动补全 CONFIG_PACKAGE_ 前缀。
# ================================================================
apply_manifest() {
    local binary_list="$1"
    local exclude_list="$2"
    local source_list="$3"
    local pkg

    # 二进制注入包：.config 禁用（源码不编译，只走 ipk 注入）
    for pkg in $binary_list; do
        sed -i "s/.*CONFIG_PACKAGE_${pkg}.*/# CONFIG_PACKAGE_${pkg} is not set/" .config 2>/dev/null || true
    done

    # 排除包：.config 禁用，不注入
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
