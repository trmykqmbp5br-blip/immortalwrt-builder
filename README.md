# ImmortalWrt Builder — 24.10.6 x86_64

基于 P3TERX/Actions-OpenWrt 模板，为 Intel J5040 软路由定制的 ImmortalWrt 24.10.6 固件。

## 固件特性

- ImmortalWrt 24.10.6 x86_64 (kernel 6.6)
- IA32_EMULATION（32位应用支持）
- 网卡驱动: 仅保留 igc (Intel I225/I226 2.5GbE)
- mwan3 双 WAN 负载均衡
- SmartDNS + DDNS
- Docker + dockerman
- BBR 拥塞控制 (kmod-tcp-bbr)
- CPU 定频 (luci-app-cpufreq)
- 默认 IP: 192.168.100.1
- SSH 密钥登录预置

## 使用方式

### GitHub Actions 远程构建

手动触发：GitHub → Actions → Build ImmortalWrt → Run workflow

### 刷机与还原

刷机后恢复配置备份：

```bash
sysupgrade -r immortalwrt-backup-20260510-with-pkgs.tar.gz
```

## 优化说明

- 禁用 BTF 调试信息（加速编译）
- 禁用 FTRACE/KPROBE/KEXEC/CRASH_DUMP
- 禁用音频/WiFi/多余网卡驱动
- 删除 PassWall / OpenClash 等第三方包
- 启用 ccache 编译缓存
- GitHub Actions 自动清理旧 Release

## 文件结构

```
├── .github/workflows/build.yml    # GitHub Actions 构建工作流
├── .config                         # OpenWrt 配置
├── diy-part1.sh                    # 自定义软件源
├── diy-part2.sh                    # IA32_EMULATION 内核配置
├── files/etc/dropbear/             # SSH 授权密钥
├── files/etc/uci-defaults/         # 首次启动脚本
├── files/etc/config/               # 默认配置（网络/mwan3/smartdns）
└── release.txt                     # Release 说明
```

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
