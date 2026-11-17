# -*- coding: utf-8 -*-
"""列出 H5 路由表里与充值/钱包/余额相关的路径。"""
import io
import os
import re

p = os.path.join(os.environ.get("TEMP", "."), "recharge_app.js")
t = io.open(p, encoding="utf-8", errors="ignore").read()

pat = re.compile(r'path:"([^"]+)"[^}]{0,160}?title:"([^"]*)"')
for m in pat.finditer(t):
    path, title = m.group(1), m.group(2)
    if any(k in path for k in ("recharge", "wallet", "balance")) or any(
        k in title for k in ("充值", "余额", "钱包")
    ):
        print(path, "|", title)

print("---- all paths ----")
for m in re.finditer(r'path:"([^"]+)"', t):
    print(m.group(1))
