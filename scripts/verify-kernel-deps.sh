#!/bin/bash
# scripts/verify-kernel-deps.sh — 验证 BINARY 包的内核依赖是否在 .config 中启用
#
# 调用时机：在 prepare-binary.sh 之后、make download 之前
# (由 diy-part2.sh 调用，此时 config-manifest.sh 已 source，变量 BINARY_SOURCE/BINARY_KERNEL_DEPS 等已定义)
#
# 如果检查失败，输出缺失的配置并 exit 1 阻断构建。

CONFIG_FILE=".config"
MISSING_DEPS=()

echo "==> Verifying kernel dependencies for BINARY packages..."

# ==========================================
# 1. 校验声明式依赖 (BINARY_KERNEL_DEPS)
# ==========================================
if [ "${#BINARY_KERNEL_DEPS[@]}" -gt 0 ]; then
    for pkg in "${!BINARY_KERNEL_DEPS[@]}"; do
        # 检查该包是否在当前 BINARY 清单中
        if echo " $CONFIG_MANIFEST_BINARY " | grep -q " $pkg "; then
            for config in ${BINARY_KERNEL_DEPS[$pkg]}; do
                local state
                state=$(./scripts/config --state "$config" 2>/dev/null || echo "n")
                if [ "$state" != "y" ] && [ "$state" != "m" ]; then
                    MISSING_DEPS+=("$config (required by declared pkg: $pkg)")
                fi
            done
        fi
    done
fi

# ==========================================
# 2. 校验 ipk 自动提取的 kmod 依赖
# ==========================================
IPK_CACHE_DIR="files/etc/ipk-cache"

if [ -d "$IPK_CACHE_DIR" ] && ls "$IPK_CACHE_DIR"/*.ipk 1>/dev/null 2>&1; then
    for ipk_file in "$IPK_CACHE_DIR"/*.ipk; do
        [ -f "$ipk_file" ] || continue
        pkg_name=$(basename "$ipk_file" | sed 's/_.*//')

        # 提取 ipk control.tar.gz/xz 中的 control 文件
        local control_data
        control_data=$(ar p "$ipk_file" control.tar.gz 2>/dev/null | tar xzf - ./control -O 2>/dev/null)
        if [ -z "$control_data" ]; then
            control_data=$(ar p "$ipk_file" control.tar.xz 2>/dev/null | tar xJf - ./control -O 2>/dev/null)
        fi

        if [ -n "$control_data" ]; then
            # 提取 Depends 行中的 kmod-xxx 依赖
            local kmod_deps
            kmod_deps=$(echo "$control_data" \
                | awk '/^Depends:/{gsub(/Depends: /,""); print}' \
                | tr ',' '\n' \
                | grep '^ *kmod-' \
                | sed 's/^ *//')

            for kmod in $kmod_deps; do
                local config="CONFIG_PACKAGE_${kmod}"
                local state
                state=$(./scripts/config --state "$config" 2>/dev/null || echo "n")
                if [ "$state" != "y" ] && [ "$state" != "m" ]; then
                    MISSING_DEPS+=("$config (required by ipk: $pkg_name -> $kmod)")
                fi
            done
        fi
    done
fi

# ==========================================
# 3. 结果处理
# ==========================================
if [ "${#MISSING_DEPS[@]}" -gt 0 ]; then
    echo ""
    echo "ERROR: Missing kernel configs for BINARY packages:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Suggested fix: add these to your kernel-config section in diy-part2.sh:"
    for dep in "${MISSING_DEPS[@]}"; do
        local config_name
        config_name=$(echo "$dep" | awk '{print $1}')
        echo "  ./scripts/config --enable ${config_name}"
    done
    echo ""
    echo "NOTE: Do NOT run 'make defconfig' after adding these!"
    exit 1
else
    echo "OK: All kernel dependencies for BINARY packages satisfied."
fi
