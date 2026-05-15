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
    if [ -n "${GH_TOKEN:-}" ]; then
        curl -sL -H "Authorization: Bearer $GH_TOKEN" "$url" 2>/dev/null
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
download_gh_release() {
    local repo="$1" pattern="$2" output="$3"
    local resp
    resp=$(github_api_get "https://api.github.com/repos/${repo}/releases/latest?per_page=100") || return 1
    local dl_url
    dl_url=$(echo "$resp" \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && return 1
    github_release_dl "$dl_url" "$output" || return 1
    [ -s "$output" ] && return 0 || return 1
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
        cp "$bin" "$FILES_DIR/$target_dir/"
        chmod +x "$FILES_DIR/$target_dir/$(basename "$bin")"
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
            /^Package: / {name=$2}
            /^Filename: / {file=$2}
            /^$/ { if (name==pkg) { print file; exit }; name="" }
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
                local repo="${payload%%:*}"
                local pattern="${payload#*:}"
                [ "$repo" = "$pattern" ] && pattern="$pkg"
                echo "  $pkg (GitHub: $repo)"
                if download_gh_release "$repo" "$pattern" "${TMPDIR}/${pkg}.ipk"; then
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
generate_boot_script() {
    local FILES_DIR="$1"
    local UCI_SCRIPT="$FILES_DIR/etc/uci-defaults/99-install-ipk-cache.sh"
    mkdir -p "$(dirname "$UCI_SCRIPT")"

    cat > "$UCI_SCRIPT" << 'UCIEOF'
#!/bin/sh
# 99-install-ipk-cache.sh — 首次启动安装预置 ipk
# prepare-binary.sh 自动生成，全部成功后才自删
#
# 安装顺序：按名称分组，保证核心包先于界面包安装
# 重试：每包最多 3 次，失败继续，不阻塞后续

IPK_DIR="/etc/ipk-cache"
RETRY_FILE="/etc/ipk-cache/.retry_count"
MAX_RETRY=3
LOG="/etc/config/ipk-install.log"

[ -d "$IPK_DIR" ] || exit 0

# 加载重试计数
declare -A RETRIES
[ -f "$RETRY_FILE" ] && . "$RETRY_FILE"

# 收集 ipk 列表，按优先级排序：
# 1. 非 luci 开头包（核心依赖）
# 2. luci-app-*（主应用）
# 3. luci-i18n-* / luci-theme-*（界面/翻译）
SORTED=""
for grp in "a" "b" "c"; do
    for ipk in "$IPK_DIR"/*.ipk; do
        [ -f "$ipk" ] || continue
        base=$(basename "$ipk" .ipk)
        case "$grp" in
            a) case "$base" in luci-app-*|luci-i18n-*|luci-theme-*) continue;; esac ;;
            b) case "$base" in luci-app-*) ;; *) continue;; esac ;;
            c) case "$base" in luci-i18n-*|luci-theme-*) ;; *) continue;; esac ;;
        esac
        SORTED="$SORTED $ipk"
    done
done

echo "[$(date)] Starting ipk install (max ${MAX_RETRY} retries each)..." >> "$LOG"
echo "  Order: core -> app -> i18n" >> "$LOG"

all_ok=0
for ipk in $SORTED; do
    base=$(basename "$ipk" .ipk)
    cnt="${RETRIES[$base]:-0}"

    if [ "$cnt" -ge "$MAX_RETRY" ]; then
        echo "  SKIP $base (failed ${cnt} times, exceeded max)" >> "$LOG"
        all_ok=1
        continue
    fi

    # 尝试安装
    opkg install "$ipk" --force-reinstall --force-overwrite --force-depends >> "$LOG" 2>&1
    rc=$?

    if [ "$rc" -eq 0 ]; then
        rm -f "$ipk"
        unset RETRIES[$base]
        echo "  OK  $base" >> "$LOG"
    else
        RETRIES[$base]=$((cnt + 1))
        all_ok=1
        echo "  FAIL $base (attempt $((cnt+1))/$MAX_RETRY)" >> "$LOG"
    fi
done

# 保存重试计数供下次启动
{
    echo "# retry counters"
    for k in "${!RETRIES[@]}"; do
        echo "RETRIES[$k]=${RETRIES[$k]}"
    done
} > "$RETRY_FILE"

if [ "$all_ok" -eq 0 ]; then
    echo "[$(date)] All ipk installed successfully, cleaning up..." >> "$LOG"
    rm -f "$RETRY_FILE"
    exit 0  # uci-defaults 框架自动删脚本
else
    echo "[$(date)] Some ipk installs still pending after this boot" >> "$LOG"
    exit 1  # 保留脚本下次重试
fi
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
