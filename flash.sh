#!/bin/bash
# ===============================================================
# flash.sh — 一键构建 + 刷写 ImmortalWrt 24.10.6（带 IA32_EMULATION）
#
# 原理:
#   1) 通过 gh CLI 触发 GitHub Actions 远程构建
#   2) 等待构建完成，下载固件
#   3) 上传到路由器，通过 SSH 刷写
#   4) 恢复备份
#
# 前置要求:
#   - gh CLI (已登录 GitHub)
#   - SSH 密钥 id_ed25519_claude 在本目录下
#   - 路由器备份文件 immortalwrt-backup-*.tar.gz 在本目录下
# ===============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ROUTER_IP="192.168.100.1"
SSH_KEY="./id_ed25519_claude"
GITHUB_REPO="trmykqmbp5br-blip/immortalwrt-builder"

# ============= 颜色定义 =============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ============= 前置检查 =============
check_prereqs() {
    echo "====================== 检查前置条件 ======================"

    # gh CLI
    if ! command -v gh &>/dev/null; then
        error "gh CLI 未安装，请先安装 https://cli.github.com/"
        exit 1
    fi
    info "gh CLI 可用"

    # SSH key
    if [ ! -f "$SSH_KEY" ]; then
        warn "SSH 密钥 $SSH_KEY 未找到，尝试从上级目录复制..."
        if [ -f "../id_ed25519_claude" ]; then
            cp "../id_ed25519_claude" . && chmod 600 id_ed25519_claude
            info "已复制 SSH 密钥"
        else
            error "SSH 密钥不存在"
            exit 1
        fi
    fi
    chmod 600 "$SSH_KEY" 2>/dev/null || true
    info "SSH 密钥就绪"

    # SSH connectivity
    if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
         "root@$ROUTER_IP" "echo alive" &>/dev/null; then
        error "无法连接到路由器 $ROUTER_IP"
        exit 1
    fi
    info "路由器连接正常 ($ROUTER_IP)"

    # 查找备份文件
    BACKUP_FILE=$(ls immortalwrt-backup-*.tar.gz 2>/dev/null | tail -1 || true)
    if [ -z "$BACKUP_FILE" ]; then
        warn "未找到本地备份文件，将在路由器上创建新备份"
        CREATE_BACKUP=true
    else
        info "使用备份文件: $BACKUP_FILE"
        CREATE_BACKUP=false
    fi

    # 检查 Git 仓库是否已推送
    if [ ! -d ".git" ]; then
        warn "当前目录不是 Git 仓库，请先执行 git init 并 push 到 GitHub"
        warn "项目模板使用: https://github.com/P3TERX/Actions-OpenWrt"
        exit 1
    fi

    echo ""
}

# ============= 触发远程构建 =============
trigger_build() {
    echo "====================== 触发 GitHub Actions 构建 ======================"

    local ROOTFS_SIZE="${1:-1024}"
    local DOCKER="${2:-yes}"

    echo "参数: rootfs_size=$ROOTFS_SIZE MB, docker=$DOCKER"

    # 触发 workflow
    gh workflow run build.yml \
        -R "$GITHUB_REPO" \
        -f rootfs_size="$ROOTFS_SIZE" \
        -f include_docker="$DOCKER" \
        -f enable_pppoe="no" \
        --ref main 2>&1 || {
        error "触发构建失败，请检查仓库名和 workflow 名称"
        exit 1
    }
    info "构建任务已触发"

    # 获取 run ID
    sleep 5
    RUN_ID=$(gh run list -R "$GITHUB_REPO" --workflow build.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
    if [ -n "$RUN_ID" ]; then
        info "构建任务 ID: $RUN_ID"
    fi
}

# ============= 等待构建完成 =============
wait_build() {
    echo "====================== 等待构建完成 ======================"
    echo "构建耗时约 1.5-3 小时，可使用 Ctrl+C 中断后重新运行本脚本的下载步骤"
    echo ""

    gh run watch -R "$GITHUB_REPO" --exit-status 2>&1 || {
        error "构建失败，请检查 GitHub Actions 日志"
        gh run view -R "$GITHUB_REPO" --log --job build 2>/dev/null | tail -50 || true
        exit 1
    }
    info "构建成功"
}

# ============= 下载固件 =============
download_firmware() {
    echo "====================== 下载固件 ======================"

    local run_id="${1:-}"
    local dl_flags="-R $GITHUB_REPO"

    if [ -n "$run_id" ]; then
        dl_flags="$dl_flags $run_id"
    fi

    mkdir -p ./firmware-download
    gh run download $dl_flags --dir ./firmware-download 2>&1 || {
        error "下载固件失败"
        exit 1
    }

    # 查找生成的固件
    FIRMWARE_FILE=$(find ./firmware-download -name '*squashfs-combined-efi.img.gz' 2>/dev/null | head -1 || true)
    if [ -z "$FIRMWARE_FILE" ]; then
        FIRMWARE_FILE=$(find ./firmware-download -name '*.img.gz' -o -name '*.bin' 2>/dev/null | head -1 || true)
    fi

    if [ -z "$FIRMWARE_FILE" ]; then
        warn "未找到固件文件，列出下载内容:"
        find ./firmware-download -type f | head -20
        exit 1
    fi

    info "固件文件: $FIRMWARE_FILE"
    ls -lh "$FIRMWARE_FILE"
}

# ============= 在路由器上创建新备份 =============
create_backup_on_router() {
    echo "====================== 在路由器上创建备份 ======================"

    local backup_name="immortalwrt-backup-$(date +%Y%m%d).tar.gz"

    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@$ROUTER_IP" \
        "sysupgrade -b -k /tmp/$backup_name" 2>&1

    # 下载备份到本地
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "root@$ROUTER_IP:/tmp/$backup_name" "./$backup_name" 2>&1

    BACKUP_FILE="$backup_name"
    info "备份已创建: $BACKUP_FILE ($(ls -lh $BACKUP_FILE | awk '{print $5}'))"
}

# ============= 上传并刷写 =============
flash_router() {
    echo "====================== 上传固件到路由器 ======================"

    local firmware="$1"
    local fw_name=$(basename "$firmware")
    local remote_fw="/tmp/$fw_name"

    # 上传固件
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
        "$firmware" "root@$ROUTER_IP:$remote_fw" 2>&1
    info "固件已上传到路由器"

    # 上传备份
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
            "$BACKUP_FILE" "root@$ROUTER_IP:/tmp/backup.tar.gz" 2>&1
        info "备份文件已上传到路由器"
    else
        warn "未找到备份文件，将不恢复配置"
    fi

    echo ""
    echo "====================== 准备刷写 ======================"
    echo "⚠️  即将刷写固件！路由器将会重启！"
    echo "   固件: $fw_name"
    echo "   备份: $(basename $BACKUP_FILE 2>/dev/null || echo '无')"
    echo ""
    echo -n "确认刷写？(yes/NO): "
    read -r CONFIRM

    if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
        info "已取消刷写"
        info "固件保留在: $firmware"
        info "备份保留在: $BACKUP_FILE"
        exit 0
    fi

    echo "开始刷写..."

    # 解压固件（如果是 .gz）
    local flash_file="$remote_fw"
    if [[ "$firmware" == *.gz ]]; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@$ROUTER_IP" \
            "gunzip -f $remote_fw && echo '解压完成'" 2>&1
        flash_file="${remote_fw%.gz}"
    fi

    # 执行 sysupgrade 恢复备份并刷写
    # 使用 -f 指定备份文件（如果有），-n 不保存旧配置
    local restore_flag=""
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@$ROUTER_IP" \
            "[ -f /tmp/backup.tar.gz ]" 2>/dev/null; then
        restore_flag="-f /tmp/backup.tar.gz"
    fi

    echo "执行: sysupgrade $restore_flag $flash_file"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@$ROUTER_IP" \
        "sysupgrade $restore_flag $flash_file" 2>&1 || true

    echo ""
    info "刷写命令已发送，路由器正在重启..."
    info "等待约 3 分钟后尝试连接..."
    echo ""
    echo "完成后执行以下步骤手动恢复备份:"
    echo "  如果刷写时传了 -f 备份文件，配置会自动恢复"
    echo "  否则: scp -i id_ed25519_claude backup.tar.gz root@192.168.100.1:/tmp/"
    echo "        ssh -i id_ed25519_claude root@192.168.100.1 'tar xzf /tmp/backup.tar.gz -C /'"
}

# ============= 主菜单 =============
main() {
    echo "================================================================"
    echo "   ImmortalWrt 一键构建 + 刷写脚本"
    echo "   版本: 24.10.6 | 内核: 6.6 + IA32_EMULATION"
    echo "================================================================"
    echo ""

    check_prereqs

    echo ""
    echo "请选择操作模式:"
    echo "  1) 完整流程 (构建 → 下载 → 刷写)"
    echo "  2) 仅触发构建"
    echo "  3) 仅下载并刷写 (构建已完成)"
    echo "  4) 仅刷写本地固件"
    echo ""
    echo -n "请选择 (1/2/3/4): "
    read -r MODE

    case "$MODE" in
        2)
            ROOTFS="${1:-1024}"
            trigger_build "$ROOTFS"
            info "查看进度: gh run view -R $GITHUB_REPO --web"
            ;;
        3)
            download_firmware ""
            flash_router "$FIRMWARE_FILE"
            [ "$CREATE_BACKUP" = true ] && create_backup_on_router
            ;;
        4)
            echo -n "固件文件路径: "
            read -r FW_PATH
            if [ -f "$FW_PATH" ]; then
                flash_router "$FW_PATH"
            else
                error "文件不存在: $FW_PATH"
                exit 1
            fi
            ;;
        1|*)
            ROOTFS="${1:-1024}"
            trigger_build "$ROOTFS"
            wait_build
            download_firmware "$RUN_ID"
            [ "$CREATE_BACKUP" = true ] && create_backup_on_router
            flash_router "$FIRMWARE_FILE"
            ;;
    esac
}

main "$@"
