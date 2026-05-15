# Build Workflow 构建流程

## 概述

基于 GitHub Actions 的 ImmortalWrt 24.10.6 x86_64 固件自动构建。核心原则：

- **ImmortalWrt 系统自带包**（DEFAULT_PACKAGES）→ 源码编译
- **所有第三方包** → 从 feed/GitHub 下载预编译 ipk，首次启动 `opkg install`
- **缓存**：dl 缓存下载好的源码包，ccache 缓存编译产物

---

## GitHub Actions 工作流（`.github/workflows/build.yml`）

### 步骤顺序

```
1. Prepare environment    # 安装依赖、释放磁盘
2. Checkout               # 检出 builder 仓库
3. Clone source code      # git clone ImmortalWrt v24.10.6
4. Restore dl cache       # 恢复下载缓存到 /workdir/openwrt/dl/
5. Restore ccache         # 恢复编译缓存到 /home/runner/.ccache/
6. Configure feeds        # diy-part1.sh + ./scripts/feeds update -a
7. Install feeds          # ./scripts/feeds install -a
8. Apply custom config    # diy-part2.sh（核心步骤，见下文）
9. Download sources       # make download -j$(nproc)
10. Save dl cache         # if: always() 失败也保存
11. Compile firmware      # make -j$(nproc) V=s
12. Save ccache           # if: always() 失败也保存
13. Verify binary inject  # 检查 binary-manifest.json 的 skipped 包
14. Release               # gh release create + 清理旧 Release
```

---

## 缓存策略

### dl 缓存（源码包缓存）

```yaml
# key 基于 feeds 配置哈希，feeds 不变则不产生新缓存条目
key: dl-${{ env.REPO_BRANCH }}-${{ hashFiles('feeds.conf.default', 'diy-part1.sh') }}
restore-keys: |
  dl-${{ env.REPO_BRANCH }}-

# 保存（无条件）
if: always()
continue-on-error: true
```

- 每次构建（包括失败）都保存一份 dl 缓存，key 带 `run_id`
- 恢复时先精确匹配，再用前缀回退，总能找到最近的有效缓存
- 历史缓存被 GitHub 自动驱逐（限额 10GB）时不影响最新缓存

### ccache 缓存（编译缓存）

```yaml
# .config 中必须设置
CONFIG_CCACHE_DIR="/home/runner/.ccache"

# 恢复
key: ccache-${{ env.REPO_BRANCH }}-${{ github.run_id }}
restore-keys: |
  ccache-${{ env.REPO_BRANCH }}-
  ccache-${{ env.REPO_BRANCH }}

# 保存（无条件）
if: always()
continue-on-error: true
```

**关键**：OpenWrt 的 `rules.mk` 会 export `CCACHE_DIR`，覆盖环境变量。`.config` 中 `CONFIG_CCACHE_DIR` 为空时 → export `CCACHE_DIR=""` → ccache 使用 XDG 默认 `~/.cache/ccache`，与 GitHub cache action 路径不匹配。必须显式设为 `/home/runner/.ccache`。

---

## 第三方包处理架构

### 核心文件

| 文件 | 作用 |
|------|------|
| `scripts/config-manifest.sh` | 声明 BINARY_SOURCE（每包的下载来源）和包清单 |
| `scripts/manifest-lib.sh` | `apply_manifest()` 写入 .config（禁用/启用） |
| `shell/prepare-binary.sh` | 下载 ipk 到 `files/etc/ipk-cache/`，生成 uci-defaults 脚本 |
| `diy-part2.sh` | 编排器，按序执行上述脚本 |

### 包分类

```
BINARY（第三方包，不编译，开机装 ipk）
├── feed:luci       — USTC 镜像 /releases/24.10.6/packages/x86_64/luci/
├── feed:packages   — USTC 镜像 /releases/24.10.6/packages/x86_64/packages/
├── feed:base       — USTC 镜像 /releases/24.10.6/packages/x86_64/base/
├── gh:owner/repo   — GitHub Releases（ipk 匹配）
└── gh-bin:         — GitHub Releases（tar.gz 提取 ELF 到 files/）

SOURCE（显式启用源码编译的包，很少用）
└─ 仅用于需要在 .config 中 =y 但不属于 DEFAULT_PACKAGES 的 feed 包

EXCLUDE（禁用，不编译不安装）
└─ 存在冲突或有问题的包（如 luci-app-fchomo）
```

### manifest-lib.sh 的 apply_manifest()

```
BINARY 包 → ./scripts/config --disable → make 跳过编译
EXCLUDE 包 → ./scripts/config --disable → make 跳过编译
SOURCE 包 → ./scripts/config --enable → make 正常编译
```

使用 OpenWrt 官方 `scripts/config` 工具（精确 key 操作，无 sed 子串误伤）。

调用时机：必须在 make defconfig 之后执行，且之后绝不再执行 make defconfig。否则 Kconfig 引擎会根据 depends on/select 关系把 BINARY 包复活。

---

## 数据流

### 编译阶段（Apply custom config）

```
config-manifest.sh
  ├─ 声明 BINARY_SOURCE[smartdns]="feed:packages"
  ├─ BINARY 清单 = smartdns luci-app-openclash docker ...
  └─ apply_manifest()  →  写入 .config（禁用所有 BINARY 包）

diy-part2.sh → kernel-config/runtime patches
  → CCACHE_DIR 注入 .config
  → make defconfig（OpenWrt 计算 Kconfig 依赖）
  → config-manifest.sh + apply_manifest()
      ├─ scripts/config --disable（BINARY 包，精确 key，无 sed 误伤）
      └─ scripts/config --enable（SOURCE 包）
  → prepare-binary.sh
      ├─ feed:packages smartdns → download_feed_pkg()
      │   └─ curl USTC 镜像 → 下载 smartdns_*.ipk → files/etc/ipk-cache/
      ├─ gh:vernesong/OpenClash → download_gh_release()
      │   └─ GitHub API → 下载 luci-app-openclash_*.ipk → files/etc/ipk-cache/
      ├─ gh-bin: → download_gh_binary() → 解压 tar.gz 提取 ELF → files/usr/bin/
      └─ 生成 uci-defaults/99-install-ipk-cache.sh
  → 二次 make download（补新添加包的源码）
```

【关键】apply_manifest 必须在 make defconfig 之后执行，且之后绝不再执行 make defconfig。

### 首次启动阶段（uci-defaults）

```
99-install-ipk-cache.sh  ← uci-defaults 框架自动执行
  ├─ 排序：核心包 → luci-app-* → luci-i18n-*/luci-theme-*
  ├─ opkg install --force-reinstall --force-overwrite --force-depends
  ├─ 失败包写入 /etc/ipk-cache/.retry_count，最多重试 3 次
  ├─ 全部成功 → exit 0 → 脚本自删
  └─ 有失败 → exit 1 → 保留脚本下次启动重试
```

---

## BINARY_SOURCE 声明格式

```bash
# feed 源 — 从 USTC 镜像下载预编译 ipk
BINARY_SOURCE[包名]="feed:{luci|packages|base}"

# GitHub Release — 从最新 Release 下载 ipk
BINARY_SOURCE[包名]="gh:owner/repo"
# pattern 默认用包名，可自定义
BINARY_SOURCE[包名]="gh:owner/repo:pattern_regex"

# GitHub Release binary — 下载 tar.gz，提取 ELF 到指定目录
BINARY_SOURCE[包名]="gh-bin:owner/repo:pattern_regex:target_dir"
```

---

## 当前 BINARY 清单

### 代理/VPN
- `luci-app-openclash` → `gh:vernesong/OpenClash`

### DNS
- `smartdns` → `feed:packages`
- `luci-app-smartdns` → `feed:luci`
- `luci-i18n-smartdns-zh-cn` → `feed:luci`

### 实用工具
- `luci-i18n-diskman-zh-cn` → `feed:luci`
- `luci-i18n-filemanager-zh-cn` → `feed:luci`
- `luci-app-ttyd` / `luci-i18n-ttyd-zh-cn` → `feed:luci`
- `openssh-sftp-server` → `feed:packages`
- `luci-i18n-ddns-zh-cn` / `ddns-scripts-aliyun` / `ddns-scripts` → `feed:luci/packages`
- `luci-i18n-acme-zh-cn` / `luci-app-acme` / `acme` / `acme-acmesh` / `acme-acmesh-dnsapi` → `feed:luci/packages`
- `socat` → `feed:packages`
- `iperf3` → `feed:packages`
- `luci-i18n-irqbalance-zh-cn` → `feed:luci`
- `luci-i18n-upnp-zh-cn` → `feed:luci`
- `speedtest-go` → `feed:packages`
- `tcpdump` → `feed:base`

### 主题
- `luci-theme-argon` / `luci-app-argon-config` / `luci-i18n-argon-config-zh-cn` → `feed:luci`

### Docker（条件包含，INCLUDE_DOCKER=yes 时）
- `docker` / `dockerd` / `containerd` / `runc` / `tini` / `docker-compose` → `feed:packages`
- `luci-lib-docker` / `luci-app-docker` / `luci-i18n-docker-zh-cn` → `feed:luci`
- `luci-app-dockerman` / `luci-i18n-dockerman-zh-cn` → `feed:luci`

### 商店
（暂未包含，等稳定 ipk 源）

---

## 常见问题

### 为什么 feed 包也要开机装 ipk，不编译？

编译每个包需要 1-10 分钟不等，OpenWrt 有约 5000 个包选项，全编译要 4+ 小时。预编译 ipk 直接从 ImmortalWrt 官方 USTC 镜像下载，秒级完成。

### 开机装 ipk 依赖怎么处理？

`opkg install --force-depends` 跳过依赖检查。运行时所需的依赖包是 ImmortalWrt 系统自带（DEFAULT_PACKAGES）编译进固件的，已经在 opkg 数据库中有记录。

### 如果某个第三方包在 USTC 镜像上找不到？

`download_feed_pkg` 找不到该包 → `PKG_STATUS[包名]="skipped"` → `binary-manifest.json` 记录跳过 → 构建日志和 Release notes 会列出跳过的包。

### ccache 为什么之前不生效？

OpenWrt 的 `rules.mk` 中 `export CCACHE_DIR:=$(CONFIG_CCACHE_DIR)` 覆盖了 GitHub Actions 设置的 `CCACHE_DIR` 环境变量。`.config` 中 `CONFIG_CCACHE_DIR=""` 时，export 为 `CCACHE_DIR=""` → ccache 使用 XDG 默认路径 `~/.cache/ccache`，但 GitHub cache action 保存的是 `/home/runner/.ccache` → 两者不匹配。

修复：diy-part2.sh 在 make defconfig 之前注入 `CONFIG_CCACHE_DIR="/home/runner/.ccache"` 到 .config，make defconfig 保留已设值，确保 OpenWrt 内部 export 的路径与 cache action 一致。
