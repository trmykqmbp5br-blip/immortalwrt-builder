#!/bin/bash
# scripts/verify-pkg-consistency.sh — 校验 BINARY 包前后端一致性（防呆机制）
#
# 检查：
#   1. 强制 LuCI 配对 (如 smartdns → 必须有 luci-app-smartdns)
#   2. ipk 依赖项中属于 BINARY 清单的包是否都存在于缓存中
#
# 调用时机：prepare-binary.sh 之后、make download 之前

# 如果未从 diy-part2.sh source 环境调用，则独立加载配置
if [ -z "$CONFIG_MANIFEST_BINARY" ] && [ -f "scripts/config-manifest.sh" ]; then
    . scripts/config-manifest.sh 2>/dev/null || true
fi
if [ -z "$BINARY_PACKAGES_FLAT" ] && [ -f "scripts/binary-packages.sh" ]; then
    . scripts/binary-packages.sh 2>/dev/null || true
fi

IPK_CACHE_DIR="files/etc/ipk-cache"
ERRORS=()

echo "==> Verifying BINARY package consistency (Frontend/Backend pairing)..."

# ==========================================
# 1. 强制 LuCI 配对 (核心包 → luci-app-核心包)
# ==========================================
for pkg in "${BINARY_LUCI_MANDATORY[@]}"; do
    luci_pkg="luci-app-${pkg}"
    if echo " $CONFIG_MANIFEST_BINARY " | grep -q " $pkg "; then
        if ! echo " $CONFIG_MANIFEST_BINARY " | grep -q " $luci_pkg "; then
            ERRORS+=("Core '${pkg}' is in BINARY manifest, but LuCI interface '${luci_pkg}' is missing.")
        fi
    fi
done

# ==========================================
# 2. ipk 依赖项检查
# ==========================================
if [ -d "$IPK_CACHE_DIR" ] && [ "$(ls "$IPK_CACHE_DIR"/*.ipk 2>/dev/null | wc -l)" -gt 0 ]; then
    # 缓存中所有包名
    local cached_names=""
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
        if [ -z "$control_data" ]; then
            control_data=$(ar p "$ipk_file" control.tar.xz 2>/dev/null | tar xJf - ./control -O 2>/dev/null)
        fi

        if [ -n "$control_data" ]; then
            deps=$(echo "$control_data" \
                | awk '/^Depends:/{gsub(/Depends: /,""); print}' \
                | tr ',' '\n' \
                | awk '{print $1}' \
                | sed 's/^ *//')

            for dep in $deps; do
                # 仅检查 BINARY 清单中的包之间的依赖
                # 忽略系统包 (libc, libopenssl, kmod-* 等)
                if echo " $CONFIG_MANIFEST_BINARY " | grep -q " $dep "; then
                    if ! echo "$cached_names" | grep -q " $dep "; then
                        ERRORS+=("'${pkg_name}' depends on '${dep}', but '${dep}' is not in ipk cache.")
                    fi
                fi
            done
        fi
    done
fi

# ==========================================
# 3. 结果
# ==========================================
if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo ""
    echo "ERROR: BINARY package consistency check failed:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    echo ""
    echo "Add the missing package to scripts/config-manifest.sh"
    exit 1
else
    echo "OK: All BINARY packages have consistent frontend/backend pairing."
fi
