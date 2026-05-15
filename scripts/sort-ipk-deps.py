#!/usr/bin/env python3
"""
scripts/sort-ipk-deps.py — 构建期 IPK 依赖拓扑排序

解析 IPK 包间的依赖关系，生成 DAG 安装顺序，
使开机安装时按依赖顺序安装，避免运行时缺失。

用法: python3 scripts/sort-ipk-deps.py [ipk_cache_dir]
默认: files/etc/ipk-cache
输出: {ipk_cache_dir}/install_order.list
"""

import os
import sys
import subprocess
from collections import defaultdict, deque

IPK_DIR = sys.argv[1] if len(sys.argv) > 1 else "files/etc/ipk-cache"
OUTPUT_LIST = os.path.join(IPK_DIR, "install_order.list")


def extract_control(ipk_path):
    for comp in ['control.tar.gz', 'control.tar.xz']:
        try:
            r = subprocess.run(['ar', 'p', ipk_path, comp],
                               capture_output=True, check=True, timeout=30)
            tar_flag = 'xzf' if 'gz' in comp else 'xJf'
            r2 = subprocess.run(['tar', tar_flag, '-', './control', '-O'],
                                input=r.stdout, capture_output=True, timeout=30)
            if r2.returncode == 0 and r2.stdout:
                return r2.stdout.decode('utf-8', errors='ignore')
        except Exception:
            continue
    return ""


def parse_control(text):
    pkg_name = None
    deps = []
    for line in text.splitlines():
        if line.startswith("Package:"):
            pkg_name = line.split(":", 1)[1].strip()
        elif line.startswith("Depends:"):
            dep_str = line.split(":", 1)[1].strip()
            deps = [d.split()[0].strip() for d in dep_str.split(',') if d.strip()]
    return pkg_name, deps


def main():
    if not os.path.isdir(IPK_DIR):
        open(OUTPUT_LIST, 'w').close()
        return

    ipk_files = sorted(f for f in os.listdir(IPK_DIR) if f.endswith('.ipk'))
    if not ipk_files:
        open(OUTPUT_LIST, 'w').close()
        return

    # Parse all ipks
    pkg_map = {}  # pkg_name -> filename
    dep_map = {}  # pkg_name -> [deps]
    for fn in ipk_files:
        path = os.path.join(IPK_DIR, fn)
        name, deps = parse_control(extract_control(path))
        if name:
            pkg_map[name] = fn
            dep_map[name] = deps

    local_pkgs = set(pkg_map.keys())

    # Build DAG: edge dep -> pkg (dep must be installed before pkg)
    graph = defaultdict(list)
    in_degree = {p: 0 for p in local_pkgs}
    for pkg, deps in dep_map.items():
        for dep in deps:
            if dep in local_pkgs:
                graph[dep].append(pkg)
                in_degree[pkg] += 1

    # Kahn's algorithm
    queue = deque([p for p in local_pkgs if in_degree[p] == 0])
    sorted_pkgs = []
    while queue:
        curr = queue.popleft()
        sorted_pkgs.append(curr)
        for n in graph[curr]:
            in_degree[n] -= 1
            if in_degree[n] == 0:
                queue.append(n)

    if len(sorted_pkgs) != len(local_pkgs):
        print(f"[sort] Warning: circular dep, fallback to alpha order", file=sys.stderr)
        sorted_pkgs = sorted(local_pkgs)

    with open(OUTPUT_LIST, 'w') as f:
        for pkg in sorted_pkgs:
            f.write(pkg_map[pkg] + '\n')
    print(f"[sort] Generated {OUTPUT_LIST} ({len(sorted_pkgs)} pkgs)")


if __name__ == "__main__":
    main()
