#!/usr/bin/env python3
"""在 include/kernel-defaults.mk 中注入 olddefconfig 步骤。

用法: python3 kernel-config-patch.py <path/to/kernel-defaults.mk>

在 vermagic 行之后插入 $(KERNEL_MAKE) olddefconfig，
使内核新旧选项能被自动填充默认值，避免 syncconfig exit 2 导致编译中断。
"""

import sys


def inject_olddefconfig(mk_path: str) -> None:
    with open(mk_path, "r") as f:
        content = f.read()

    old = "MKHASH) md5 > $(LINUX_DIR)/.vermagic\nendef"
    new = "MKHASH) md5 > $(LINUX_DIR)/.vermagic\n\t$(KERNEL_MAKE) olddefconfig 2>&1\nendef"

    if new in content:
        print(f"  olddefconfig already present in {mk_path}")
        return

    if old not in content:
        print(f"  WARNING: vermagic pattern not found in {mk_path}, cannot inject olddefconfig")
        return

    content = content.replace(old, new)
    with open(mk_path, "w") as f:
        f.write(content)

    print(f"  olddefconfig injected into {mk_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <kernel-defaults.mk path>", file=sys.stderr)
        sys.exit(1)

    inject_olddefconfig(sys.argv[1])
