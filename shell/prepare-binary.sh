#!/bin/bash
# prepare-binary.sh — 从 USTC 镜像 / GitHub Releases 下载二进制 ipk 并注入 rootfs
#
# 原理: 下载 .ipk → 解压 data.tar → 合并到 files/ 目录，
#       固件编译时自动打包进 rootfs。
#
# 用法: source shell/prepare-binary.sh && prepare_binary_packages "files" "$BINARY_PACKAGES"

IMMORTALWRT_RELEASE="24.10.6"
ARCH="x86_64"
MIRROR_BASE="https://mirrors.ustc.edu.cn/immortalwrt/releases/${IMMORTALWRT_RELEASE}/packages/${ARCH}"

# ================================================================
# 包 → 下载源映射
# 格式:  feed:<feed名>
#        gh:<owner/repo>:<文件名正则>
#        gh-bin:<owner/repo>:<文件名正则>:<解压后路径>
# ================================================================
resolve_pkg_url() {
    local pkg="$1"
    case "$pkg" in
        # === Luci feed ===
        luci-app-smartdns)          echo "feed:luci" ;;
        luci-i18n-smartdns-zh-cn)   echo "feed:luci" ;;
        luci-app-ttyd)              echo "feed:luci" ;;
        luci-i18n-ttyd-zh-cn)       echo "feed:luci" ;;
        luci-i18n-ddns-zh-cn)       echo "feed:luci" ;;
        luci-i18n-acme-zh-cn)       echo "feed:luci" ;;
        luci-app-acme)              echo "feed:luci" ;;
        luci-i18n-irqbalance-zh-cn) echo "feed:luci" ;;
        luci-i18n-upnp-zh-cn)       echo "feed:luci" ;;
        luci-theme-argon)           echo "feed:luci" ;;
        luci-app-argon-config)      echo "feed:luci" ;;
        luci-i18n-argon-config-zh-cn) echo "feed:luci" ;;
        luci-i18n-diskman-zh-cn)    echo "feed:luci" ;;
        luci-i18n-filemanager-zh-cn) echo "feed:luci" ;;

        # === Packages feed ===
        openssh-sftp-server)        echo "feed:packages" ;;
        socat)                      echo "feed:packages" ;;
        iperf3)                     echo "feed:packages" ;;
        ddns-scripts)               echo "feed:packages" ;;
        ddns-scripts-aliyun)        echo "feed:packages" ;;
        acme)                       echo "feed:packages" ;;
        acme-acmesh)                echo "feed:packages" ;;
        acme-acmesh-dnsapi)         echo "feed:packages" ;;

        # === Base feed ===
        tcpdump)                    echo "feed:base" ;;

        # === GitHub Releases (ipk) ===
        luci-app-openclash)
            echo "gh:vernesong/OpenClash:luci-app-openclash_[0-9].*\\.ipk" ;;
        smartdns)
            echo "gh:pymumu/smartdns:smartdns\\.[0-9].*\\.${ARCH}-openwrt-all\\.ipk" ;;

        # === Store（由 prepare-store.sh 单独处理） ===
        luci-app-store)             echo "store" ;;

        # === GitHub Releases (binary tar.gz → 解压到 /usr/bin) ===
        speedtest-go)
            echo "gh-bin:librespeed/speedtest-go:speedtest-go_.*linux_amd64\\.tar\\.gz:usr/bin" ;;

        *) echo "unknown:$pkg" ;;
    esac
}

# ================================================================
# 下载器
# ================================================================

# 从 GitHub Releases 下载 ipk
download_gh_release() {
    local repo="$1"
    local pattern="$2"
    local output="$3"
    local dl_url=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && return 1
    curl -sL "$dl_url" -o "$output"
}

# 从 GitHub Releases 下载 binary tar.gz，解压到 files/
download_gh_binary() {
    local repo="$1"
    local pattern="$2"
    local target_dir="$3"
    local tmpdir=$(mktemp -d)
    local dl_url=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep "browser_download_url" \
        | grep -E "$pattern" \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)"/\1/')
    [ -z "$dl_url" ] && { rm -rf "$tmpdir"; return 1; }
    local archive="${tmpdir}/archive.tar.gz"
    curl -sL "$dl_url" -o "$archive"
    tar -xzf "$archive" -C "$tmpdir" 2>/dev/null
    # 找到解压后的二进制文件（排除目录自身）
    local bin=$(find "$tmpdir" -maxdepth 2 -type f -executable 2>/dev/null | head -1)
    if [ -z "$bin" ]; then
        # 可能是非可执行权限，取第一个非 .txt/.md 文件
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

# 从 ImmortalWrt 仓库 feed 下载 ipk（通过 USTC 镜像）
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

# 解压 ipk data 到目标目录
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
# ================================================================
prepare_binary_packages() {
    FILES_DIR="${1:-files}"
    local WANTED="${2:-}"
    [ -z "$WANTED" ] && return 0

    echo "=== 注入二进制第三方包 ==="
    local TMPDIR=$(mktemp -d)
    mkdir -p "$FILES_DIR"

    for pkg in $WANTED; do
        local src=$(resolve_pkg_url "$pkg")
        local method="${src%%:*}"
        local payload="${src#*:}"
        local ok=false

        case "$method" in
            feed)
                local feed="$payload"
                echo "  处理: $pkg (feed: $feed)"
                download_feed_pkg "$feed" "$pkg" "${TMPDIR}/${pkg}.ipk" && ok=true
                if $ok && extract_ipk_to "${TMPDIR}/${pkg}.ipk" "$FILES_DIR"; then
                    echo "    ✓ $pkg 已注入"
                else
                    echo "    WARNING: $pkg 下载或解压失败"
                fi
                ;;
            gh)
                local repo="$payload"
                local pattern="${repo#*:}"
                repo="${repo%%:*}"
                echo "  处理: $pkg (GitHub: $repo)"
                download_gh_release "$repo" "$pattern" "${TMPDIR}/${pkg}.ipk" && ok=true
                if $ok && extract_ipk_to "${TMPDIR}/${pkg}.ipk" "$FILES_DIR"; then
                    echo "    ✓ $pkg 已注入"
                else
                    echo "    WARNING: $pkg 下载或解压失败"
                fi
                ;;
            gh-bin)
                local repo="${payload%%:*}"
                local rest="${payload#*:}"
                local pattern="${rest%:*}"
                local target_dir="${rest##*:}"
                echo "  处理: $pkg (GitHub binary: $repo)"
                if download_gh_binary "$repo" "$pattern" "$target_dir"; then
                    echo "    ✓ $pkg 已注入到 files/$target_dir/"
                else
                    echo "    WARNING: $pkg 下载或解压失败"
                fi
                ;;
            store)
                echo "  跳过: $pkg (由 prepare-store.sh 处理)"
                ;;
            *)
                echo "  WARNING: $pkg 无可用下载源，跳过"
                ;;
        esac
    done

    rm -rf "$TMPDIR"
    echo "=== 二进制包注入完成 ==="
}
