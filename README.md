# ImmortalWrt Builder — 24.10.6 x86_64

基于 P3TERX/Actions-OpenWrt 模板，为 Intel J5040 软路由定制的 ImmortalWrt 24.10.6 固件。

## 固件特性

- ImmortalWrt 24.10.6 x86_64 (kernel 6.6, LLVM 编译)
- IA32_EMULATION（32 位应用支持，musl + glibc 双运行时）
- 网卡驱动: igc (I225/I226) + e1000e, igb, ixgbe, r8125, r8168, vmxnet3, USB 网卡等
- mwan3 双 WAN 负载均衡（自动检测网口数 ≥2 时启用）
- SmartDNS（DoT/DoH/UDP 多上游，去广告规则自动更新）
- Docker + dockerman（构建时可选择开关）
- BBR 拥塞控制 (kmod-tcp-bbr)
- CPU 定频 (luci-app-cpufreq)
- 默认 IP: 192.168.100.1
- SSH 密钥登录预置
- 自动检测网口数量：单网口 DHCP 模式，多网口静态 IP + 双 WAN
- 安全加固: RELRO Full, FORTIFY_SOURCE, SECCOMP

## 使用方式

### GitHub Actions 远程构建

1. Fork 本仓库
2. 在 Settings → Secrets and variables → Actions 中添加 Secrets（可选，推荐）：
   - `PPPOE_WAN_ACCOUNT` / `PPPOE_WAN_PASSWORD` — 第一条宽带的 PPPoE 凭证
   - `PPPOE_WANB_ACCOUNT` / `PPPOE_WANB_PASSWORD` — 第二条宽带的 PPPoE 凭证
3. Actions → Build ImmortalWrt → Run workflow
4. 填写参数后触发构建（约 1.5-3 小时）
5. 构建完成后在 Releases 下载固件

### 使用 flash.sh 一键构建 + 刷写

```bash
chmod +x flash.sh
./flash.sh
```

### 刷机与还原

刷机后**手动**恢复配置备份：

```bash
# 1. 上传备份到路由器
scp -i id_ed25519_claude immortalwrt-backup-*-with-pkgs.tar.gz root@192.168.100.1:/tmp/

# 2. 恢复备份（自动重新安装已记录的软件包）
ssh -i id_ed25519_claude root@192.168.100.1 'sysupgrade -r /tmp/immortalwrt-backup-*-with-pkgs.tar.gz'
```

flash.sh 脚本仅负责构建+刷写，不处理备份，备份由用户手动管理。

## 32 位应用运行指南

### 原理

固件预置了以下 32 位库：

| 文件 | 路径 | 说明 |
|------|------|------|
| `ld-musl-i386.so.1` | `/lib/` | musl 动态链接器（也是 libc） |
| `libgcc_s.so.1` | `/lib32/` | GCC 运行时（异常处理/栈展开） |
| `libstdc++.so.6` | `/lib32/` | C++ 标准库 |
| `libatomic.so.1` | `/lib32/` | 原子操作支持 |
| `libopenssl.so.3` | `/lib32/` | TLS/加密 |
| `libcurl.so.4` | `/lib32/` | HTTP 客户端 |
| `libz.so.1` | `/lib32/` | 压缩/解压 |

### 使用方式

**纯静态链接的 32 位程序** — 直接运行，不需要任何额外操作：

```bash
./static-32bit-binary
```

**动态链接的 32 位程序** — 必须通过 `run-i386` 启动：

```bash
run-i386 /path/to/32bit-binary [args...]
```

`run-i386` 会通过 `--library-path` 告诉 32 位 musl 动态链接器优先从 `/lib32/` 搜索库，避免错误加载 `/lib/` 下的 64 位版本。

直接执行 32 位动态链接程序会因加载到 64 位 .so 而失败。

### 添加更多 32 位库

如果需要的库不在预置列表中：

```bash
# 从 ImmortalWrt i386 官方镜像中提取
wget https://downloads.immortalwrt.org/releases/24.10.6/targets/x86/generic/immortalwrt-24.10.6-x86-generic-generic-ext4-rootfs.img.gz
gunzip immortalwrt-24.10.6-x86-generic-generic-ext4-rootfs.img.gz
mkdir /tmp/i386-rootfs
mount -o loop,ro immortalwrt-24.10.6-x86-generic-generic-ext4-rootfs.img /tmp/i386-rootfs
cp /tmp/i386-rootfs/usr/lib/你需要.so /lib32/
umount /tmp/i386-rootfs
```



| 参数 | 说明 | 默认值 |
|------|------|--------|
| rootfs_size | 根文件系统大小 (MB) | 4096 |
| include_docker | 是否包含 Docker | yes |
| enable_pppoe | 是否启用 PPPoE 拨号 | no |
| pppoe_wan_account | 第一条宽带账号 | - |
| pppoe_wan_password | 第一条宽带密码 | - |
| pppoe_wanb_account | 第二条宽带账号 | - |
| pppoe_wanb_password | 第二条宽带密码 | - |

## 优化说明

- 禁用 BTF 调试信息（加速编译，减小内核体积）
- 禁用 FTRACE/KPROBE/KEXEC/CRASH_DUMP
- 精简网卡/音频驱动（移除 HDA 声卡、WiFi 等）
- 仅启用必要的虚拟化网卡驱动 (vmxnet3, e1000e)
- 启用 ccache 编译缓存
- GitHub Actions 自动保留最近 3 个 Release
- 使用 LLVM/Clang 构建（部分组件）

## 文件结构

```
├── .github/workflows/build.yml    # GitHub Actions 构建工作流
├── .config                         # OpenWrt 配置 (x86_64)
├── diy-part1.sh                    # 自定义软件源（可添加第三方 feed）
├── diy-part2.sh                    # 内核配置 + Docker/Rootfs 开关
├── files/etc/dropbear/             # SSH 授权密钥
├── files/etc/uci-defaults/         # 首次启动脚本（动态网络配置）
├── files/etc/config/               # 默认配置（网络/mwan3/smartdns）
├── flash.sh                        # 一键构建+刷写到路由器
└── release.txt                     # Release 说明
```

## 安全注意事项

- **请勿在 Workflow 输入框中直接填写真实 PPPoE 密码**（会出现在构建日志中）
- 推荐使用 GitHub Actions Secrets 存储敏感凭证
- 构建日志中的密码会以明文显示，仅用于调试
- 定期更换路由器 SSH 密钥和宽带密码

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
