# ImmortalWrt Builder — 24.10.6 x86_64

基于 P3TERX/Actions-OpenWrt 模板，构建带 IA32_EMULATION（32位应用支持）的 ImmortalWrt 24.10.6 固件。

## 使用方式

### 1. GitHub Actions 远程构建

手动触发：GitHub → Actions → Build ImmortalWrt → Run workflow

或使用 gh CLI：
```bash
gh workflow run build.yml -R trmykqmbp5br-blip/immortalwrt-builder
```

### 2. 本地一键刷写

```bash
bash flash.sh
```

脚本支持 4 种模式：
- **完整流程**：触发构建 → 等待 → 下载 → 刷写
- **仅触发构建**：远程构建，稍后手动刷写
- **仅下载并刷写**：构建已完成，下载并刷写
- **仅刷写本地固件**：使用本地已下载的固件刷写

## 固件特性

- ImmortalWrt 24.10.6 x86_64
- 内核 6.6 + IA32_EMULATION（支持 32 位应用程序）
- PassWall + OpenClash
- mwan3 双 WAN 负载均衡
- SmartDNS + DDNS
- Docker 支持
- 默认 IP: 192.168.100.1

## 文件结构

```
├── .github/workflows/build.yml    # GitHub Actions 构建工作流
├── .config                         # OpenWrt 配置
├── diy-part1.sh                    # 自定义软件源
├── diy-part2.sh                    # IA32_EMULATION 内核配置
├── files/etc/uci-defaults/         # 首次启动脚本
├── files/etc/config/               # 默认配置（网络/mwan3/smartdns）
└── flash.sh                        # 本地一键刷写脚本
```

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
