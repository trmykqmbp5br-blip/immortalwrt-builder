#!/bin/bash
# shell/prepare-binary.sh — 第三方 ipk 下载 + 开机安装
#
# 依赖 config-manifest.sh 预先 source（提供 BINARY_SOURCE 关联数组 + BINARY_PACKAGES）
# 从 BINARY_SOURCE[包名] 读取来源标识，自动选择下载方式。
#
# 下载的 ipk 存入 files/etc/ipk-cache/，由 uci-defaults 在首次启动时 opkg install。
# gh-bin: 来源直接解压二进制到 files/ 对应目录（不走 opkg）。
#
# 用法: source shell/prepare-binary.sh && prepare_binary_packages "files" "$BINARY_PACKAGES"

IMMORTALWRT_RELEASE="24.10.6"
ARCH="x86_64"

# ================================================================
# 解析 BINARY_SOURCE 并下载
# ================================================================

# GitHub API 请求（带 token 防限流）
github_api_get() {
    local url="$1"
    local auth=""
    [ -n "${GH_TOKEN:-}" ] && auth="-H \"Authorization: Bearer $GH_TOKEN\""
    curl -sL $auth "$url" 2>/dev/null
}

# GitHub Release 下载
github_release_dl() {
    local url="$1"
    local output="$2"
    local auth=""
    [ -n "${GH_TOKEN:-}" ] && auth="-H \"Authorization: Bearer $GH_TOKEN\""
    curl -sL --retry 3 --retry-delay 5 --connect-timeout 15 $auth "$url" -o "$output" 2>/dev/null
}

# 从 GitHub Releases 下载 ipk
download_gh_release() {
    local repo="$1"
    local pattern="$2"
    local output="$3"
    local resp=$(github_api_get "https://api.github.com/repos/${repo}/releases/latest?per_page=100")
    local dl_url=$(echo "$resp" \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    if [ -z "$dl_url" ]; then
        if echo "$resp" | grep -qi "rate limit"; then
            echo "  > ERROR: GitHub API rate limited! Set GH_TOKEN to avoid this." >&2
        fi
        echo "  > Pattern '$pattern' not found in releases" >&2
        return 1
    fi
    github_release_dl "$dl_url" "$output"
    [ -s "$output" ] && return 0 || return 1
}

# 从 GitHub Releases 下载 binary tar.gz，解压到 files/ 下指定目录
download_gh_binary() {
    local repo="$1"
    local pattern="$2"
    local target_dir="$3"
    local tmpdir=$(mktemp -d)
    local resp=$(github_api_get "https://api.github.com/repos/${repo}/releases/latest?per_page=100")
    local dl_url=$(echo "$resp" \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    if [ -z "$dl_url" ]; then
        echo "  > Pattern '$pattern' not found in releases" >&2
        rm -rf "$tmpdir"; return 1
    fi
    local archive="${tmpdir}/archive.tar.gz"
    github_release_dl "$dl_url" "$archive" || { rm -rf "$tmpdir"; return 1; }
    tar -xzf "$archive" -C "$tmpdir" 2>/dev/null
    local bin=$(find "$tmpdir" -maxdepth 2 -type f -executable 2>/dev/null | head -1)
    if [ -z "$bin" ]; then
        bin=$(find "$tmpdir" -maxdepth 2 -type f ! -name "*.txt" ! -name "*.md" ! -name "checksums*" -exec file {} \; | grep ELF | cut -d: -f1 | head -1)
    fi
    if [ -n "$bin" ]; then
        mkdir -p "$FILES_DIR/$target_dir"
        cp "$bin" "$FILES_DIR/$target_dir/"
        chmod +x "$FILES_DIR/$target_dir/$(basename "$bin")"
        rm -rf "$tmpdir"
        return 0
    fi
    rm -rf "$tmpdir"
    return 1
}

# ================================================================
# prepare_binary_packages — 主入口
# 遍历 $WANTED 列表，下载并保存 ipk 到 files/etc/ipk-cache/。
# gh-bin 来源直接解压二进制到 files/ 指定目录。
# 最后生成 binary-manifest.json 并创建 uci-defaults 开机安装脚本。
# ================================================================
prepare_binary_packages() {
    local FILES_DIR="${1:-files}"
    local WANTED="${2:-}"
    local pkg

    [ -z "$WANTED" ] && return 0

    echo "=== Download 3rd-party packages ==="
    local TMPDIR=$(mktemp -d)
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
            gh)
                local repo="${payload%%:*}"
                local pattern="${payload#*:}"
                [ "$repo" = "$pattern" ] && pattern="$pkg"
                echo "  pkg: $pkg (GitHub: $repo)"
                if download_gh_release "$repo" "$pattern" "${TMPDIR}/${pkg}.ipk"; then
                    cp "${TMPDIR}/${pkg}.ipk" "$IPK_CACHE_DIR/"
                    echo "    + $pkg.ipk saved to /etc/ipk-cache/"
                    PKG_STATUS["$pkg"]="injected"
                    has_ipk=true
                else
                    echo "    - $pkg skipped (download failed)"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            gh-bin)
                local repo="${payload%%:*}"
                local rest="${payload#*:}"
                local the_pattern="${rest%:*}"
                local target_dir="${rest##*:}"
                [ "$repo" = "$rest" ] && { echo "  - $pkg skipped (bad spec)"; PKG_STATUS["$pkg"]="skipped"; continue; }
                echo "  pkg: $pkg (GitHub binary: $repo)"
                if download_gh_binary "$repo" "$the_pattern" "$target_dir"; then
                    echo "    + $pkg binary extracted to files/$target_dir/"
                    PKG_STATUS["$pkg"]="injected"
                else
                    echo "    - $pkg skipped (download failed)"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            store)
                echo "  pkg: $pkg (handled by prepare-store.sh)"
                PKG_STATUS["$pkg"]="pending"
                ;;
            *)
                echo "  - $pkg skipped (unrecognized source: $src)"
                PKG_STATUS["$pkg"]="bad_source"
                ;;
        esac
    done

    # 如果有 ipk 需要开机安装，生成 uci-defaults 脚本
    if $has_ipk; then
        local UCI_SCRIPT="$FILES_DIR/etc/uci-defaults/99-install-ipk-cache.sh"
        mkdir -p "$(dirname "$UCI_SCRIPT")"
        cat > "$UCI_SCRIPT" << 'UCIEOF'
#!/bin/sh
# 99-install-ipk-cache.sh — 首次启动安装预置 ipk
# 由 prepare-binary.sh 自动生成，uci-defaults 框架保证只执行一次后自删

IPK_DIR="/etc/ipk-cache"
[ -d "$IPK_DIR" ] || exit 0

for ipk in "$IPK_DIR"/*.ipk; do
    [ -f "$ipk" ] || continue
    opkg install "$ipk" --force-depends 2>/dev/null && \
        rm -f "$ipk"
done

exit 0
UCIEOF
        chmod +x "$UCI_SCRIPT"
        echo "  uci-defaults script created: $UCI_SCRIPT"
    fi

    # 生成 binary-manifest.json
    generate_manifest "$FILES_DIR" "$WANTED" PKG_STATUS

    rm -rf "$TMPDIR"
    echo "=== Done ==="
}

# ================================================================
# generate_manifest — 生成注入结果清单
# ================================================================
generate_manifest() {
    local files_dir="$1"
    local wanted="$2"
    local -n status_ref="$3"
    local pkg

    local output="${files_dir}/etc/binary-manifest.json"
    mkdir -p "${files_dir}/etc"

    local total=0 injected=0 skipped=0 pending=0
    for pkg in $wanted; do
        : $((total++))
        case "${status_ref[$pkg]}" in
            injected) : $((injected++));;
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
            $first || echo ","
            first=false
            local st="${status_ref[$pkg]:-unknown}"
            local src="${BINARY_SOURCE[$pkg]:-unknown}"
            echo -n "    \"$pkg\": {\"status\": \"$st\", \"source\": \"$src\"}"
        done
        echo ""
        echo "  },"
        echo "  \"summary\": {"
        echo "    \"total_requested\": $total,"
        echo "    \"total_injected\": $injected,"
        echo "    \"total_skipped\": $skipped,"
        echo "    \"total_pending\": $pending"
        echo "  }"
        echo "}"
    } > "$output"

    if [ -n "${GITHUB_WORKSPACE:-}" ]; then
        cp "$output" "${GITHUB_WORKSPACE}/binary-manifest.json" 2>/dev/null || true
    fi
}
