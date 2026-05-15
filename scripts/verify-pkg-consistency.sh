#!/bin/bash
# scripts/verify-pkg-consistency.sh — 校验 BINARY 包前后端一致性与运行时依赖闭环
#
# 检查：
#   1. 强制 LuCI 配对 (smartdns → luci-app-smartdns)
#   2. ipk 依赖闭环（运行时依赖的包必须在缓存或系统默认中）
#
# 调用时机：prepare-binary.sh 之后、make download 之前

# 独立加载
if [ -z "$CONFIG_MANIFEST_BINARY" ] && [ -f "scripts/config-manifest.sh" ]; then
    . scripts/config-manifest.sh 2>/dev/null || true
fi
if [ -z "$BINARY_PACKAGES_FLAT" ] && [ -f "scripts/binary-packages.sh" ]; then
    . scripts/binary-packages.sh 2>/dev/null || true
fi

IPK_CACHE_DIR="files/etc/ipk-cache"
ERRORS=()

echo "==> Verifying BINARY package consistency and runtime dependencies..."

# ==========================================
# 1. 强制 LuCI 配对 (防后端缺前端)
# ==========================================
for pkg in "${BINARY_LUCI_MANDATORY[@]}"; do
    if echo " $CONFIG_MANIFEST_BINARY " | grep -q " $pkg "; then
        luci_pkg="luci-app-${pkg}"
        if ! echo " $CONFIG_MANIFEST_BINARY " | grep -q " $luci_pkg "; then
            ERRORS+=("Core '${pkg}' included, but mandatory LuCI '${luci_pkg}' missing.")
        fi
    fi
done

# ==========================================
# 2. ipk 依赖闭环校验
# ==========================================
if [ -d "$IPK_CACHE_DIR" ] && [ "$(ls "$IPK_CACHE_DIR"/*.ipk 2>/dev/null | wc -l)" -gt 0 ]; then
    # 缓存中所有包名
    cached_names=""
    for ipk in "$IPK_CACHE_DIR"/*.ipk; do
        [ -f "$ipk" ] || continue
        name=$(basename "$ipk" | sed 's/_.*//')
        cached_names="$cached_names $name"
    done

    for ipk_file in "$IPK_CACHE_DIR"/*.ipk; do
        [ -f "$ipk_file" ] || continue
        pkg_name=$(basename "$ipk_file" | sed 's/_.*//')

        # 提取 control 文件
        control_data=$(ar p "$ipk_file" control.tar.gz 2>/dev/null | tar xzf - ./control -O 2>/dev/null)
        [ -z "$control_data" ] && \
            control_data=$(ar p "$ipk_file" control.tar.xz 2>/dev/null | tar xJf - ./control -O 2>/dev/null)

        if [ -n "$control_data" ]; then
            arch=$(echo "$control_data" | awk '/^Architecture:/{print $2}')
            if [ -n "$arch" ] && [ "$arch" != "x86_64" ] && [ "$arch" != "all" ]; then
                ERRORS+=("Package '${pkg_name}' has incompatible architecture '${arch}'. Expected x86_64 or all.")
            fi
            deps=$(echo "$control_data" \
                | awk '/^Depends:/{gsub(/Depends: /,""); print}' \
                | tr ',' '\n' \
                | awk '{print $1}')

            for dep in $deps; do
                # 忽略系统底层依赖
                [[ "$dep" == "libc" ]] && continue
                [[ "$dep" == "kernel" ]] && continue
                [[ "$dep" =~ ^kmod- ]] && continue

                # 检查：是否在缓存中 或 在 BINARY 清单中（由系统默认提供）
                in_cache=$(echo "$cached_names" | grep -wq "$dep" && echo 1 || echo 0)
                in_manifest=$(echo " $CONFIG_MANIFEST_BINARY " | grep -q " $dep " && echo 1 || echo 0)

                if [ "$in_cache" -eq 0 ] && [ "$in_manifest" -eq 0 ]; then
                    ERRORS+=("'${pkg_name}' depends on '${dep}', not in ipk-cache or manifest. May crash at runtime!")
                fi
            done
        fi
    done
fi

# ==========================================
# 结果
# ==========================================
if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo ""
    echo "ERROR: BINARY package consistency check failed:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
else
    echo "OK: All BINARY packages consistent and runtime-safe."
fi
