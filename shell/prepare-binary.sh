#!/bin/bash
# shell/prepare-binary.sh — 二进制 ipk 下载 + 注入 + 清单生成
#
# 依赖 config-manifest.sh 预先 source（提供 BINARY_SOURCE 关联数组 + BINARY_PACKAGES）
# 从 BINARY_SOURCE[包名] 读取来源标识，自动选择下载方式。
#
# 用法: source shell/prepare-binary.sh && prepare_binary_packages "files" "$BINARY_PACKAGES"

IMMORTALWRT_RELEASE="24.10.6"
ARCH="x86_64"
MIRROR_BASE="https://mirrors.ustc.edu.cn/immortalwrt/releases/${IMMORTALWRT_RELEASE}/packages/${ARCH}"

# ================================================================
# 解析 BINARY_SOURCE 并下载
# ================================================================

# 从 GitHub Releases 下载 ipk
download_gh_release() {
    local repo="$1"
    local pattern="$2"
    local output="$3"
    local dl_url=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest?per_page=100" 2>/dev/null \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && return 1
    curl -sL "$dl_url" -o "$output"
}

# 从 GitHub Releases 下载 binary tar.gz，解压到 files/ 下指定目录
download_gh_binary() {
    local repo="$1"
    local pattern="$2"
    local target_dir="$3"
    local tmpdir=$(mktemp -d)
    local dl_url=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest?per_page=100" 2>/dev/null \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && { rm -rf "$tmpdir"; return 1; }
    local archive="${tmpdir}/archive.tar.gz"
    curl -sL "$dl_url" -o "$archive"
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

# 从 ImmortalWrt USTC 镜像 feed 下载 ipk
download_feed_pkg() {
    local feed="$1"
    local pkg="$2"
    local output="$3"
    local feed_url="${MIRROR_BASE}/${feed}"
    local pkg_file=$(curl -sL "${feed_url}/Packages.gz" 2>/dev/null \
        | gzip -d 2>/dev/null \
        | awk -v pkg="$pkg" '
            /^Package: / {name=$2}
            /^Filename: / {file=$2}
            /^$/ { if (name==pkg) { print file; exit }; name="" }
        ')
    [ -z "$pkg_file" ] && return 1
    curl -sL "${feed_url}/${pkg_file}" -o "$output"
}

# 解压 ipk 中的 data 归档到目标目录
extract_ipk_to() {
    local ipk="$1"
    local dest="$2"
    local tmpdir=$(mktemp -d)
    mkdir -p "$dest"
    tar -xzf "$ipk" -C "$tmpdir" ./data.tar.gz 2>/dev/null || \
    tar -xzf "$ipk" -C "$tmpdir" ./data.tar.xz 2>/dev/null || \
    { rm -rf "$tmpdir"; return 1; }
    if [ -f "$tmpdir/data.tar.gz" ]; then
        tar -xzf "$tmpdir/data.tar.gz" -C "$dest" 2>/dev/null
    elif [ -f "$tmpdir/data.tar.xz" ]; then
        tar -xJf "$tmpdir/data.tar.xz" -C "$dest" 2>/dev/null
    else
        rm -rf "$tmpdir"
        return 1
    fi
    rm -rf "$tmpdir"
    return 0
}

# ================================================================
# prepare_binary_packages — 主入口
# 读取 BINARY_SOURCE（由 config-manifest.sh 提供全局关联数组），
# 遍历 $WANTED 列表，下载并注入每个包。
# 最后生成 binary-manifest.json。
#
# 用法: prepare_binary_packages "files目录" "包列表"
# 示例: prepare_binary_packages "$REPO_ROOT/files" "$BINARY_PACKAGES"
# ================================================================
prepare_binary_packages() {
    local FILES_DIR="${1:-files}"
    local WANTED="${2:-}"
    local pkg

    [ -z "$WANTED" ] && return 0

    echo "=== 注入二进制第三方包 ==="
    local TMPDIR=$(mktemp -d)
    mkdir -p "$FILES_DIR"

    # 记录每个包的处理状态
    declare -A PKG_STATUS

    for pkg in $WANTED; do
        # 从 BINARY_SOURCE 获取来源标识（由 config-manifest.sh 声明）
        local src="${BINARY_SOURCE[$pkg]:-}"
        [ -z "$src" ] && { PKG_STATUS["$pkg"]="no_source"; continue; }

        local method="${src%%:*}"
        local payload="${src#*:}"
        local ok=false

        case "$method" in
            feed|ustc)
                local feed="$payload"
                echo "  处理: $pkg (feed: $feed)"
                download_feed_pkg "$feed" "$pkg" "${TMPDIR}/${pkg}.ipk" && ok=true
                if $ok && extract_ipk_to "${TMPDIR}/${pkg}.ipk" "$FILES_DIR"; then
                    echo "    ✓ $pkg 已注入"
                    PKG_STATUS["$pkg"]="injected"
                else
                    echo "  [SKIP] $pkg (not found)"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            gh)
                local repo="${payload%%:*}"
                local pattern="${payload#*:}"
                # 如果 payload 没有 ":"，则 pattern 为空；此时用包名做默认模式
                [ "$repo" = "$pattern" ] && pattern="$pkg"
                echo "  处理: $pkg (GitHub: $repo)"
                download_gh_release "$repo" "$pattern" "${TMPDIR}/${pkg}.ipk" && ok=true
                if $ok && extract_ipk_to "${TMPDIR}/${pkg}.ipk" "$FILES_DIR"; then
                    echo "    ✓ $pkg 已注入"
                    PKG_STATUS["$pkg"]="injected"
                else
                    echo "  [SKIP] $pkg (not found)"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            gh-bin)
                local repo="${payload%%:*}"
                local rest="${payload#*:}"
                local the_pattern="${rest%:*}"
                local target_dir="${rest##*:}"
                [ "$repo" = "$rest" ] && { echo "  [SKIP] $pkg (bad gh-bin spec)"; PKG_STATUS["$pkg"]="skipped"; continue; }
                echo "  处理: $pkg (GitHub binary: $repo)"
                if download_gh_binary "$repo" "$the_pattern" "$target_dir"; then
                    echo "    ✓ $pkg 已注入到 files/$target_dir/"
                    PKG_STATUS["$pkg"]="injected"
                else
                    echo "  [SKIP] $pkg (not found)"
                    PKG_STATUS["$pkg"]="skipped"
                fi
                ;;
            store)
                echo "  跳过: $pkg (由 prepare-store.sh 处理)"
                PKG_STATUS["$pkg"]="pending"
                ;;
            *)
                echo "  [SKIP] $pkg (unrecognized source: $src)"
                PKG_STATUS["$pkg"]="bad_source"
                ;;
        esac
    done

    # 生成 binary-manifest.json
    generate_injection_manifest "$FILES_DIR" "$WANTED" PKG_STATUS

    rm -rf "$TMPDIR"
    echo "=== 二进制包注入完成 ==="
}

# ================================================================
# generate_injection_manifest — 生成注入结果清单
# 写入 files/etc/binary-manifest.json（刷机后 /etc 下可见）
# 同时复制到 $GITHUB_WORKSPACE（CI 验证用）
# ================================================================
generate_injection_manifest() {
    local files_dir="$1"
    local wanted="$2"
    local -n status_ref="$3"  # nameref to associative array
    local pkg

    local output="${files_dir}/etc/binary-manifest.json"
    mkdir -p "${files_dir}/etc"

    echo "=== 生成二进制注入清单 ==="

    # 统计
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

            echo -n "    \"$pkg\": {"
            echo -n "\"status\": \"$st\", "
            echo -n "\"source\": \"$src\""
            echo -n "}"
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

    echo "  manifest written to $output"

    # 同步到 GITHUB_WORKSPACE（CI 验证用）
    if [ -n "${GITHUB_WORKSPACE:-}" ]; then
        cp "$output" "${GITHUB_WORKSPACE}/binary-manifest.json" 2>/dev/null || true
        echo "  manifest copied to \$GITHUB_WORKSPACE/binary-manifest.json"
    fi

    echo "=== 清单生成完毕 ==="
}
