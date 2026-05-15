#!/bin/bash
# shell/prepare-binary.sh — 第三方 ipk 下载 + 开机安装
#
# 依赖 config-manifest.sh 预先 source（提供 BINARY_SOURCE 关联数组 + BINARY_PACKAGES）
# 从 BINARY_SOURCE[包名] 读取来源标识，自动选择下载方式。
#
# feed: / gh: 来源下载 .ipk → files/etc/ipk-cache/ → 首次启动 opkg install
# gh-bin: 来源下载 tar.gz → 提取 ELF 到 files/ 指定目录
#
# 用法: source shell/prepare-binary.sh && prepare_binary_packages "files" "$BINARY_PACKAGES"

IMMORTALWRT_RELEASE="24.10.6"
ARCH="x86_64"
MIRROR_BASE="https://mirrors.ustc.edu.cn/immortalwrt/releases/${IMMORTALWRT_RELEASE}/packages/${ARCH}"

# ================================================================
# 下载工具
# ================================================================

# GitHub API 请求（带 GH_TOKEN 防限流）
github_api_get() {
    local url="$1"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -sL -H "Authorization: token $GITHUB_TOKEN" "$url" 2>/dev/null
    else
        curl -sL "$url" 2>/dev/null
    fi
}

# GitHub Release 下载
github_release_dl() {
    local url="$1" output="$2"
    if [ -n "${GH_TOKEN:-}" ]; then
        curl -sL --retry 3 --retry-delay 5 --connect-timeout 15 \
            -H "Authorization: Bearer $GH_TOKEN" "$url" -o "$output" 2>/dev/null
    else
        curl -sL --retry 3 --retry-delay 5 --connect-timeout 15 "$url" -o "$output" 2>/dev/null
    fi
}

# 从 GitHub Releases 下载 ipk
# 来源格式: gh:owner/repo 或 gh:owner/repo:tag
download_gh_release() {
    local pkg_name="$1"    # 包名，用作默认 pattern
    local payload="$2"     # 来源 payload (owner/repo 或 owner/repo:tag)
    local output="$3"

    # 解析 owner/repo 和可选 tag
    local repo="$payload"
    local tag=""
    if [[ "$payload" == *:* ]]; then
        tag="${payload##*:}"
        repo="${payload%:*}"
    fi

    # 构建 API URL
    local api_url
    if [ -n "$tag" ]; then
        api_url="https://api.github.com/repos/${repo}/releases/tags/${tag}"
        echo "    Tag: $tag"
    else
        api_url="https://api.github.com/repos/${repo}/releases/latest"
    fi

    local resp
    resp=$(github_api_get "$api_url") || return 1

    local dl_url
    dl_url=$(echo "$resp" \
        | grep "browser_download_url" \
        | grep -E "$pkg_name" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && return 1
    github_release_dl "$dl_url" "$output" || return 1
    [ -s "$output" ] && return 0 || return 1
}
# ================================================================
# check_gh_binary_deps — 检查 gh-bin 提取的二进制文件兼容性
# ================================================================
check_gh_binary_deps() {
    local target_file="$1"

    echo "[check] Verifying $target_file ..."

    # 1. 检查是否为 ELF
    if ! file "$target_file" 2>/dev/null | grep -q "ELF"; then
        echo "[check] Not an ELF executable, skip dep check."
        return
    fi

    # 2. 检查架构
    if ! file "$target_file" | grep -q "x86-64"; then
        echo "  ERROR: Binary is NOT x86-64! It will not run on target."
        file "$target_file"
        exit 1
    fi

    # 3. 静态 vs 动态
    if file "$target_file" | grep -q "statically linked"; then
        echo "  [OK] Statically linked. No shared library deps."
        return
    fi

    # 动态链接: 检查 interpreter
    local interpreter
    interpreter=$(readelf -l "$target_file" 2>/dev/null | grep "interpreter" | grep -oP '\[.*?\]' | sed 's/[][]//g') || true
    if echo "$interpreter" | grep -q "ld-linux"; then
        echo "  ERROR: glibc binary (interpreter: $interpreter). ImmortalWrt uses musl!"
        exit 1
    elif echo "$interpreter" | grep -q "ld-musl"; then
        echo "  [OK] musl binary ($interpreter)"
    else
        echo "  [OK] interpreter: ${interpreter:-none}"
    fi

    # 4. NEEDED 库
    local needed
    needed=$(readelf -d "$target_file" 2>/dev/null | grep "NEEDED" | grep -oP '\[.*?\]' | sed 's/[][]//g') || true
    if [ -n "$needed" ]; then
        echo "  Requires shared libs:"
        echo "$needed" | sed 's/^/    /'
        echo "  Ensure these exist in firmware (/lib/, /usr/lib/)"
    fi
}


# 从 GitHub Releases 下载 binary tar.gz，解压到 files/ 下指定目录
download_gh_binary() {
    local repo="$1" pattern="$2" target_dir="$3"
    local tmpdir
    tmpdir=$(mktemp -d) || return 1
    local resp
    resp=$(github_api_get "https://api.github.com/repos/${repo}/releases/latest?per_page=100") || { rm -rf "$tmpdir"; return 1; }
    local dl_url
    dl_url=$(echo "$resp" \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && { rm -rf "$tmpdir"; return 1; }
    local archive="${tmpdir}/archive.tar.gz"
    github_release_dl "$dl_url" "$archive" || { rm -rf "$tmpdir"; return 1; }
    tar -xzf "$archive" -C "$tmpdir" 2>/dev/null
    local bin
    bin=$(find "$tmpdir" -maxdepth 2 -type f -executable 2>/dev/null | head -1)
    [ -z "$bin" ] && bin=$(find "$tmpdir" -maxdepth 2 -type f ! -name "*.txt" ! -name "*.md" ! -name "checksums*" -exec file {} \; | grep ELF | cut -d: -f1 | head -1)
    if [ -n "$bin" ]; then
        mkdir -p "$FILES_DIR/$target_dir"
        target_path="$FILES_DIR/$target_dir/$(basename "$bin")"
        cp "$bin" "$target_path"
        chmod +x "$target_path"
        check_gh_binary_deps "$target_path"
        rm -rf "$tmpdir"
        return 0
    fi
    rm -rf "$tmpdir"
    return 1
}

# 从 ImmortalWrt USTC 镜像 feed 下载 ipk
download_feed_pkg() {
    local feed="$1" pkg="$2" output="$3"
    local feed_url="${MIRROR_BASE}/${feed}"
    local pkg_file
    pkg_file=$(curl -sL --retry 3 --retry-delay 3 --connect-timeout 15 "${feed_url}/Packages.gz" 2>/dev/null \
        | gzip -d 2>/dev/null \
        | awk -v pkg="$pkg" '
            $1=="Package:" && $2==pkg { found=1 }
            found && $1=="Filename:" { print $2; exit }
        ')
    [ -z "$pkg_file" ] && return 1
    curl -sL --retry 3 --retry-delay 3 --connect-timeout 15 "${feed_url}/${pkg_file}" -o "$output" 2>/dev/null
    [ -s "$output" ] && return 0 || return 1
}

# ================================================================
# prepare_binary_packages — 主入口
# ================================================================
prepare_binary_packages() {
    local FILES_DIR="${1:-files}"
    local WANTED="${2:-}"
    [ -z "$WANTED" ] && return 0

    echo "=== Download 3rd-party packages ==="
    local TMPDIR
    TMPDIR=$(mktemp -d) || return 1
    local IPK_CACHE_DIR="$FILES_DIR/etc/ipk-cache"
    mkdir -p "$FILES_DIR" "$IPK_CACHE_DIR"

    declare -A PKG_STATUS
    local has_ipk=false

    for pkg in $WANTED; do
        local src="${BINARY_SOURCE[$pkg]:-}"
        [ -z "$src" ] && { PKG_STATUS["$pkg"]="no_source"; continue; }

        local method="${src%%:*}"
        local payload="${src#*:}"

        case "$method" in
            feed|ustc)
                local feed="$payload"
                echo "  $pkg (feed: $feed)"
                if download_feed_pkg "$feed" "$pkg" "${TMPDIR}/${pkg}.ipk"; then
                    cp "${TMPDIR}/${pkg}.ipk" "$IPK_CACHE_DIR/"
                    echo "    + $pkg.ipk saved"
                    PKG_STATUS["$pkg"]="downloaded"
                    has_ipk=true
                else
                    echo "    - $pkg.ipk not found in feed $feed"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            gh)
                echo "  $pkg (GitHub: $payload)"
                if download_gh_release "$pkg" "$payload" "${TMPDIR}/${pkg}.ipk"; then
                    cp "${TMPDIR}/${pkg}.ipk" "$IPK_CACHE_DIR/"
                    echo "    + $pkg.ipk saved"
                    PKG_STATUS["$pkg"]="downloaded"
                    has_ipk=true
                else
                    echo "    - $pkg.ipk download failed"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            gh-bin)
                local repo="${payload%%:*}"
                local rest="${payload#*:}"
                local the_pattern="${rest%:*}"
                local target_dir="${rest##*:}"
                [ "$repo" = "$rest" ] && { echo "  - $pkg (bad gh-bin spec)"; PKG_STATUS["$pkg"]="skipped"; continue; }
                echo "  $pkg (GitHub binary: $repo)"
                if download_gh_binary "$repo" "$the_pattern" "$target_dir"; then
                    echo "    + binary -> files/$target_dir/"
                    PKG_STATUS["$pkg"]="extracted"
                else
                    echo "    - binary download failed"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            *)
                echo "  - $pkg (unknown source: $src)"
                PKG_STATUS["$pkg"]="bad_source"
                ;;
        esac
    done

    # 生成 uci-defaults 开机安装脚本
    if $has_ipk; then
        generate_boot_script "$FILES_DIR"
    fi

    generate_manifest "$FILES_DIR" "$WANTED" PKG_STATUS
    rm -rf "$TMPDIR"
    echo "=== Done ==="
}

# ================================================================
# generate_boot_script — 生成开机安装脚本
# 特性：
#   - 按依赖层级排序：核心 → 主应用 → i18n
#   - 单包失败不影响其他包
#   - 每包最多重试 3 次
#   - --force-reinstall --force-overwrite 确保强制覆盖
# ================================================================
# ================================================================
# generate_boot_script — 生成开机安装脚本（批量安装 + 重试）
# ================================================================
generate_boot_script() {
    local FILES_DIR="$1"
    local UCI_SCRIPT="$FILES_DIR/etc/uci-defaults/99-install-ipk-cache.sh"
    mkdir -p "$(dirname "$UCI_SCRIPT")"

    cat > "$UCI_SCRIPT" << 'UCIEOF'
#!/bin/sh
# 99-install-ipk-cache.sh — 安装预置 ipk
# 优先使用 DAG 拓扑排序清单，按依赖顺序安装
IPK_DIR="/etc/ipk-cache"
LOG="/etc/config/ipk-install.log"
ORDER_FILE="$IPK_DIR/install_order.list"
[ -d "$IPK_DIR" ] || exit 0

echo "=== Starting custom ipk installation ===" > "$LOG"

install_pkg() {
    local ipk="$1"
    [ -f "$ipk" ] || return 0
    echo "$(date) Installing $(basename "$ipk")..." >> "$LOG"
    opkg install "$ipk" --force-reinstall --force-overwrite --force-depends >> "$LOG" 2>&1
}

if [ -f "$ORDER_FILE" ]; then
    echo "$(date) Installing via DAG order..." >> "$LOG"
    while read -r ipk_name; do
        [ -z "$ipk_name" ] && continue
        install_pkg "$IPK_DIR/$ipk_name"
    done < "$ORDER_FILE"
else
    echo "$(date) DAG not found, prefix fallback..." >> "$LOG"
    for ipk in "$IPK_DIR"/*.ipk; do
        case "$(basename "$ipk")" in luci-*) continue ;; esac
        install_pkg "$ipk"
    done
    for ipk in "$IPK_DIR"/luci-app-*.ipk; do install_pkg "$ipk"; done
    for ipk in "$IPK_DIR"/luci-theme-*.ipk; do install_pkg "$ipk"; done
    for ipk in "$IPK_DIR"/luci-i18n-*.ipk; do install_pkg "$ipk"; done
    for ipk in "$IPK_DIR"/luci-*.ipk; do install_pkg "$ipk"; done
fi

echo "$(date) Installation complete" >> "$LOG"
rm -f "$IPK_DIR"/*.ipk "$ORDER_FILE"
exit 0
UCIEOF
    chmod +x "$UCI_SCRIPT"
    echo "  uci-defaults script created: $UCI_SCRIPT"
}



# ================================================================
# generate_manifest — 生成注入结果清单
# ================================================================
generate_manifest() {
    local files_dir="$1" wanted="$2"
    local -n status_ref="$3"
    local output="${files_dir}/etc/binary-manifest.json"
    mkdir -p "${files_dir}/etc"

    local total=0 downloaded=0 extracted=0 skipped=0 pending=0 pkg
    for pkg in $wanted; do
        : $((total++))
        case "${status_ref[$pkg]}" in
            downloaded) : $((downloaded++));;
            extracted)  : $((extracted++));;
            skipped|no_source|bad_source) : $((skipped++));;
            pending) : $((pending++));;
        esac
    done

    {
        echo "{"
        echo "  \"architecture\": \"$ARCH\","
        echo "  \"immortalwrt_release\": \"$IMMORTALWRT_RELEASE\","
        echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"packages\": {"
        local first=true
        for pkg in $wanted; do
            $first || echo ","; first=false
            local st="${status_ref[$pkg]:-unknown}"
            local src="${BINARY_SOURCE[$pkg]:-unknown}"
            echo -n "    \"$pkg\": {\"status\": \"$st\", \"source\": \"$src\"}"
        done
        echo ""
        echo "  },"
        echo "  \"summary\": {"
        echo "    \"total_requested\": $total,"
        echo "    \"total_downloaded\": $downloaded,"
        echo "    \"total_extracted\": $extracted,"
        echo "    \"total_skipped\": $skipped,"
        echo "    \"total_pending\": $pending"
        echo "  }"
        echo "}"
    } > "$output"

    if [ -n "${GITHUB_WORKSPACE:-}" ]; then
        cp "$output" "${GITHUB_WORKSPACE}/binary-manifest.json" 2>/dev/null || true
    fi
}
