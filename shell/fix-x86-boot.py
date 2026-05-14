#!/usr/bin/env python3
"""Fix x86 image Makefile: replace staging_dir/boot copy with direct kernel build tree paths."""
import sys

fn = sys.argv[1] if len(sys.argv) > 1 else "target/linux/x86/image/Makefile"

with open(fn, encoding="utf-8") as f:
    content = f.read()

old = "\t-$(CP) $(STAGING_DIR_ROOT)/boot/. $@.boot/boot/"
new = "\t-$(CP) $(LINUX_DIR)/.config $@.boot/boot/config-$(LINUX_RELEASE) 2>/dev/null || true\n\t-$(CP) $(LINUX_DIR)/System.map $@.boot/boot/System.map-$(LINUX_RELEASE) 2>/dev/null || true"

if old not in content:
    print(f"  SKIP: pattern not found in {fn}")
    sys.exit(0)

content = content.replace(old, new)
with open(fn, "w", encoding="utf-8") as f:
    f.write(content)
print(f"  patched: {fn}")
