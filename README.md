# ImmortalWrt Builder — 24.10.6 x86_64 有线网关优化固件

基于 ImmortalWrt 24.10.6 和 GitHub Actions 的自动构建固件，面向 Intel J5040 等 x86_64 软路由，定位为纯有线网关：去 WiFi、精简驱动、聚焦转发与 NAT 性能，并集成双 WAN 负载均衡、SmartDNS、Docker、BBR 等常用功能。构建过程大量使用缓存与二进制注入，在保证可维护性的前提下尽量缩短编译时间。

## 固件定位

- **纯有线网关**：移除所有无线驱动和固件（ath/mt76/b43/wl 等），只保留有线网卡驱动，适合作为旁路/主路由专注转发。
- **x86_64 + 32 位兼容**：内核启用 IA32_EMULATION，并预置 musl 32 位与 glibc 32 位双运行时，方便运行闭源 32 位程序（如某些网银/驱动插件）。
- **构建即代码**：全部配置集中在 `.config`、`diy-part1.sh`、`diy-part2.sh` 和 `scripts/` 目录，配合 GitHub Actions 一键构建，方便版本升级与定制。

## 核心特性

### 系统
- ImmortalWrt 24.10.6 x86_64，内核 6.6，部分组件使用 LLVM/Clang 构建。
- 默认 IP 192.168.100.1，预置 SSH 密钥登录，方便初次部署。
- 安全加固：RELRO Full、FORTIFY_SOURCE、SECCOMP 等编译选项。

### 网络与多 WAN
- 网卡驱动：igc (I225/I226)、e1000e、igb、ixgbe、r8125、r8168、vmxnet3 以及常见 USB 有线网卡。
- **mwan3 双 WAN 负载均衡**：构建脚本根据网口数量自动判断，单网口使用 DHCP，多网口自动配置静态 IP + 双 WAN，无需手动调整。

### DNS 与去广告
- **SmartDNS**：支持 DoT/DoH/UDP 多上游，内置去广告规则自动更新脚本，兼顾解析速度与广告过滤。

### Docker 与容器
- **Docker + dockerman**：通过构建参数 `include_docker` 控制是否包含，默认启用，方便在路由器上运行各类容器服务。

### 性能与调优
- **BBR 拥塞控制**：通过 kmod-tcp-bbr 启用，改善高延迟链路的传输性能。
- **CPU 定频**：集成 luci-app-cpufreq，可按需调节频率策略，降低功耗或提升性能。

### 32 位应用支持

预置两套 32 位运行时：
- **musl 32 位**：来自 ImmortalWrt i386 rootfs，提供 `/lib/ld-musl-i386.so.1` 和 `/lib32/*.so`。
- **glibc 32 位**：来自 Ubuntu 22.04 i386，提供 `/lib/ld-linux.so.2` 和 `/lib32/glibc/*.so`，兼容常见闭源 32 位程序。

提供 `run-i386` 包装脚本，自动识别 musl/glibc 二进制并设置正确的 `LD_LIBRARY_PATH`，避免 32 位程序误加载 64 位库。

## 构建与缓存策略

### GitHub Actions 一键构建

1. Fork 本仓库
2. 在 Actions 中选择 **Build ImmortalWrt** 工作流
3. 填写 `rootfs_size`、`include_docker` 等参数后触发构建
4. 构建完成后在 Releases 下载固件

### 缓存与二进制注入

- **dl 缓存**：基于 `feeds.conf.default` 和 `diy-part1.sh` 的哈希生成 key，仅在构建成功时保存，避免失败缓存污染；同 feeds 配置下复用缓存，加速 `make download`。
- **ccache**：key 采用"日期 + feeds 哈希"，配合 `CCACHE_MAXSIZE`、`CCACHE_COMPRESS` 以及构建后统计与超限清理，在 GitHub 10GB 限额内尽量提高命中率。
- **第三方包策略**：ImmortalWrt 自带包编译进固件；第三方包优先从 USTC 镜像下载预编译 ipk，首次启动通过 uci-defaults 批量安装，兼顾构建速度与运行时依赖管理。

### 32 位运行时 tarball 维护

`runtime/musl32.tar.gz` 和 `runtime/glibc32.tar.gz` 存放在仓库中，构建脚本自动提取并注入固件。

升级 ImmortalWrt 版本时，建议在 CI 环境中重新生成 tarball，或从构建产物 Artifacts 下载 runtime-tarballs 替换本地文件，确保 32 位库与新版内核/musl 兼容。

## 刷机与配置还原

1. 在 Releases 下载对应版本的固件。
2. 使用 `sysupgrade` 刷入（注意先备份重要数据）。
3. 刷机后通过 SSH 上传之前的备份包（含网络配置、PPPoE 账号、已安装软件包等）：

```bash
# 上传备份
scp -i id_ed25519_claude immortalwrt-backup-*-with-pkgs.tar.gz root@192.168.100.1:/tmp/

# 恢复备份（自动重装已记录的软件包）
ssh -i id_ed25519_claude root@192.168.100.1 'sysupgrade -r /tmp/immortalwrt-backup-*-with-pkgs.tar.gz'
```

备份中包含网络配置（PPPoE）、mwan3/SmartDNS 设置以及已安装软件列表（如 OpenClash/AdGuardHome 等），恢复后即可还原完整运行环境。

## 构建参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| rootfs_size | 根文件系统大小（MB） | 4096 |
| include_docker | 是否包含 Docker 相关包 | yes |

## 文件结构（简化）

```
├── .github/workflows/build.yml    # GitHub Actions 构建工作流
├── .config                         # OpenWrt 配置 (x86_64)
├── diy-part1.sh                    # 自定义软件源/feeds
├── diy-part2.sh                    # 自定义配置编排器（加载 scripts/*）
├── scripts/                        # 构建模块（内核补丁、运行时提取、包清单等）
├── files/                          # 固件预置文件（配置、SSH 密钥、uci-defaults 脚本等）
├── shell/                          # 二进制 ipk 下载与注入脚本
└── runtime/                        # 32 位运行时 tarball（musl32 / glibc32）
```

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
