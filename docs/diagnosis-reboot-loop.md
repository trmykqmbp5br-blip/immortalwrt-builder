# 反复重启问题诊断记录

## 现象

固件编译成功并刷入后，系统启动后 30 秒内反复重启。UEFI 启动，J5040 软路由，4 个 I225-V 网口。

## 已排查并修复的问题

### Fix #1 — glibc 库误放到 /lib/

**提交:** `af0506b` (后续 `d008463` 精细化)

**根因:** `diy-part2.sh` 提取 32 位 glibc 运行时库时，目标路径设为 `files/lib/`，导致 glibc 版本的 `libc.so.6`、`libpthread.so.0`、`libm.so.6` 等覆盖了 64 位 musl 系统库。系统 init 进程崩溃 → 反复重启。

**修复:** 将 glibc 运行时库目标路径改为 `files/lib32/glibc/`。`ld-linux.so.2` 仍保留在 `/lib/`（ELF 硬编码路径）。

### Fix #2 — run-i386 缺少 musl/glibc 双运行时检测

**提交:** `d008463`

**根因:** `run-i386` 直接 `exec /lib/ld-musl-i386.so.1`，如果目标程序是 glibc 链接的，会加载失败。

**修复:** 增加 `--list` 预检 + `LD_LIBRARY_PATH` 回退。

### Fix #3 — musl/glibc 两套 32 位库在 /lib32/ 中冲突

**提交:** 当前 HEAD

**根因:** glibc 提取 (`files/lib32/`) 覆盖了 musl 提取的同名库（`libgcc_s.so.1`、`libstdc++.so.6`、`libssl.so.3`、`libcrypto.so.3`、`libz.so.1`）。`run-i386` 用 musl ld 可能加载到 glibc 版本的库 → segfault。

**修复:** 将 glibc 库分离到 `/lib32/glibc/`，musl 库保留在 `/lib32/`。`run-i386` 的 glibc 回退路径改为 `LD_LIBRARY_PATH=/lib32/glibc:/lib32`。

## 仍需排查的方向

### 方向 A: J5040 C-state 深睡眠问题

Gemini Lake Refresh 系列（J5040/N5030 等）在 Linux 下存在已知的深 C-state（C8/C9/C10）BUG，进入深睡眠后无法正常唤醒导致系统崩溃。

**验证方式:** 在 GRUB 内核引导参数中添加 `intel_idle.max_cstate=1`，限制 CPU 空闲状态不超过 C1。

**修改位置:** `.config` 中 `CONFIG_GRUB_BOOTOPTS=""` → 改为 `CONFIG_GRUB_BOOTOPTS="intel_idle.max_cstate=1"`

**补充:** 如果此项无效，可进一步尝试 `processor.max_cstate=1` 或 BIOS 中关闭深 C-state。

### 方向 B: IA32_EMULATION 内核配置不一致

`diy-part2.sh` 通过修改 `target/linux/x86/config-6.6` 启用 `CONFIG_IA32_EMULATION=y`。后续 `make defconfig` 重新生成 `.config` 时可能产生配置偏差，导致内核构建出有问题的二进制。

**验证方式:**
- 构建完成后检查生成的 `build_dir/target-x86_64_musl/linux-x86_64/.config` 是否包含 `CONFIG_IA32_EMULATION=y` 及其依赖（`COMPAT_BINFMT_ELF`、`COMPAT_32BIT_TIME` 等）
- 尝试在没有 IA32_EMULATION 的情况下构建一次（注释掉 diy-part2.sh 中相关代码），确认问题是否消失

### 方向 C: 构建产物的 Bootloader 兼容性

检查刷写的镜像是否与 J5040 固件完全兼容。当前构建上传的是 `*squashfs-combined-efi.img.gz`。

**确认点:**
- BIOS 设置：UEFI 启动 + CSM 关闭/开启
- GRUB 是否正确安装到 EFI 分区
- 尝试 `ext4-combined-efi.img.gz`（非 squashfs，方便调试）

### 方向 D: igc 网卡驱动问题

I225-V 网卡（igc 驱动）有已知硬件 BUG，特定链路速度/协商状态下可能触发内核崩溃。kernel 6.6 是否有特定 igc 补丁缺失需要确认。

**验证方式:** dmesg 中有无 igc 相关错误，尝试加载 `igc` 模块参数或更新固件。

## 诊断记录

| 日期 | 操作 | 结论 |
|------|------|------|
| 2026-05 | Fix: glibc /lib/ → /lib32/glibc/ | 修复了库覆盖导致 init crash 的问题 |
| 2026-05 | Fix: run-i386 musl/glibc 双运行时 | 修复了 32 位程序兼容性问题 |
| 2026-05 | Fix: musl/glibc 库分离（/lib32/ vs /lib32/glibc/） | 消除两套 32 位库冲突 |
| 2026-05 | 当前 | 重启问题仍存在，方向 A-B 待验证 |
