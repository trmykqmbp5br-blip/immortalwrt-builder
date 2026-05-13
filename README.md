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
2. Actions → Build ImmortalWrt → Run workflow
3. 填写参数后触发构建（约 1-2 小时，首次构建需下载全部源码包，后续利用缓存大幅提速）
4. 构建完成后在 Releases 下载固件

### 刷机与还原

刷机后**手动**恢复配置备份：

```bash
# 1. 上传备份到路由器
scp -i id_ed25519_claude immortalwrt-backup-*-with-pkgs.tar.gz root@192.168.100.1:/tmp/

# 2. 恢复备份（自动重新安装已记录的软件包）
ssh -i id_ed25519_claude root@192.168.100.1 'sysupgrade -r /tmp/immortalwrt-backup-*-with-pkgs.tar.gz'
```

> 备份包含了网络配置(PPPoE 账号密码)、已安装软件包(OpenClash/AdGuardHome 等)、mwan3/SmartDNS 配置等，刷机后恢复备份即可还原完整环境。

### 构建参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| rootfs_size | 根文件系统大小 (MB) | 4096 |
| include_docker | 是否包含 Docker | yes |

## 32 位应用运行指南

### 原理

固件预置了两套 32 位运行时：

| 运行时 | 路径 | 来源 |
|--------|------|------|
| musl 32-bit | `/lib/ld-musl-i386.so.1`, `/lib32/*.so` | ImmortalWrt i386 rootfs |
| glibc 32-bit | `/lib/ld-linux.so.2`, `/lib32/glibc/*.so` | Ubuntu 22.04 i386 |

musl 32 位库:

| 文件 | 路径 | 说明 |
|------|------|------|
| `ld-musl-i386.so.1` | `/lib/` | musl 动态链接器（也是 libc） |
| `libgcc_s.so.1` | `/lib32/` | GCC 运行时（异常处理/栈展开） |
| `libstdc++.so.6` | `/lib32/` | C++ 标准库 |
| `libatomic.so.1` | `/lib32/` | 原子操作支持 |
| `libssl.so.3` | `/lib32/` | TLS/加密 |
| `libcrypto.so.3` | `/lib32/` | 加密算法 |
| `libcurl.so.4` | `/lib32/` | HTTP 客户端 |
| `libz.so.1` | `/lib32/` | 压缩/解压 |

glibc 32 位库 (在 `/lib32/glibc/`):

| 文件 | 说明 |
|------|------|
| `ld-linux.so.2` | glibc 动态链接器（ELF 硬编码 /lib/ 路径） |
| `libc.so.6`, `libpthread.so.0`, `libm.so.6` | glibc 核心运行时 |
| `libgcc_s.so.1`, `libstdc++.so.6` | GCC/C++ 运行时 |
| `libssl.so.3`, `libcrypto.so.3` | OpenSSL |
| `libz.so.1` | zlib 压缩 |

### 使用方式

**纯静态链接的 32 位程序** — 直接运行，不需要任何额外操作：

```bash
./static-32bit-binary
```

**动态链接的 32 位程序** — 通过 `run-i386` 启动：

```bash
run-i386 /path/to/32bit-binary [args...]
```

`run-i386` 自动检测二进制类型：
- musl 链接 → 使用 `/lib/ld-musl-i386.so.1` 从 `/lib32/` 加载库
- glibc 链接 → 使用 `LD_LIBRARY_PATH=/lib32/glibc:/lib32` 回退

直接执行 32 位动态链接程序会因加载到 64 位 .so 而失败。

### 运行时 tarball 维护

32 位运行时库已压缩为 tarball 提交在 `runtime/` 目录，构建脚本自动检测并使用。**升级 ImmortalWrt 版本时需要重新生成。**

生成方式：在 GitHub Actions ubuntu-22.04 运行环境中执行：

```bash
# 1. 克隆你要升级的目标版本
git clone https://github.com/immortalwrt/immortalwrt -b <新版本> /tmp/openwrt
cd /tmp/openwrt

# 2. 下载 i386 rootfs（用于 musl 32 位库）
wget https://downloads.immortalwrt.org/releases/<新版本>/targets/x86/64/immortalwrt-<新版本>-x86-64-generic-rootfs.tar.gz
mkdir -p i386-rootfs && cd i386-rootfs
wget https://downloads.immortalwrt.org/releases/<新版本>/targets/x86/generic/immortalwrt-<新版本>-x86-generic-rootfs.tar.gz
tar -xzf immortalwrt-*-x86-generic-rootfs.tar.gz
# 提取 musl 32 位文件
mkdir -p musl32
cp -a lib/ld-musl-i386.so.1 musl32/
cp -a usr/lib/libgcc_s*.so* musl32/
# ...（完整提取逻辑参考 scripts/runtime-musl32.sh）

# 3. 生成 glibc 32 位库（从 Ubuntu 22.04 i386 环境复制）
# 参考 scripts/runtime-glibc32.sh

# 4. 打包
cd musl32 && tar -czf musl32.tar.gz *
cd glibc32 && tar -czf glibc32.tar.gz *

# 5. 替换仓库中的旧文件
cp musl32.tar.gz runtime/
cp glibc32.tar.gz runtime/
```

推荐做法：直接运行 CI 构建一次（不提交 tarball），从构建产物 Artifacts 下载 `runtime-tarballs`，解压后覆盖 `runtime/` 目录。构建时 `scripts/runtime-musl32.sh` 和 `scripts/runtime-glibc32.sh` 会自动从新版本 i386 rootfs 提取最新的 32 位库。

**路径对照：**

| 文件 | 仓库路径 | 固件路径 | 来源 |
|------|---------|---------|------|
| musl 32-bit tarball | `runtime/musl32.tar.gz` | → `/lib/ld-musl-i386.so.1`, `/lib32/*.so` | ImmortalWrt i386 rootfs |
| glibc 32-bit tarball | `runtime/glibc32.tar.gz` | → `/lib/ld-linux.so.2`, `/lib32/glibc/*.so` | Ubuntu 22.04 i386 |

## 优化说明

- 禁用 BTF 调试信息（加速编译，减小内核体积）
- 禁用 FTRACE/KPROBE/KEXEC/CRASH_DUMP
- 精简网卡/音频驱动（移除 HDA 声卡、WiFi 等）
- 仅启用必要的虚拟化网卡驱动 (vmxnet3, e1000e)
- 启用 ccache + dl 缓存（分支级 key，防 10GB 堆积）
- GitHub Actions 自动保留最近 3 个 Release
- 使用 LLVM/Clang 构建（部分组件）

## 文件结构

```
├── .github/workflows/build.yml    # GitHub Actions 构建工作流
├── .config                         # OpenWrt 配置 (x86_64)
├── diy-part1.sh                    # 自定义软件源
├── diy-part2.sh                    # 自定义配置编排器
│
├── scripts/                        # 构建模块（由 diy-part2.sh 加载）
│   ├── kernel-config.sh            # IA32_EMULATION 内核补丁
│   ├── runtime-musl32.sh           # musl 32 位运行时提取
│   ├── runtime-glibc32.sh          # glibc 32 位运行时提取
│   ├── docker-toggle.sh            # Docker 包开关
│   └── build-runtime-tarballs.sh   # 运行时 tarball 生成
│
├── files/                          # 固件预置文件
│   ├── etc/config/                 # 网络/mwan3/smartdns 默认配置
│   ├── etc/dropbear/               # SSH 授权密钥
│   ├── etc/uci-defaults/           # 首次启动脚本
│   └── usr/bin/run-i386            # 32 位程序运行包装器
│
├── shell/
│   ├── custom-packages.sh          # 第三方软件包选择
│   └── prepare-store.sh            # iStore 二进制包处理
│
└── release.txt                     # Release 说明
```

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
