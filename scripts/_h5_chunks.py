# -*- coding: utf-8 -*-
"""从 webpack 运行时里找出 myWallet 页面 chunk 的文件名。"""
import io
import os
import re

p = os.path.join(os.environ.get("TEMP", "."), "recharge_app.js")
t = io.open(p, encoding="utf-8", errors="ignore").read()

# webpack chunk 映射，形如: myWallet:"a1b2c3d4"
for m in re.finditer(r'([A-Za-z0-9_]+):"([0-9a-f]{8})"', t):
    if "wallet" in m.group(1).lower() or "recharge" in m.group(1).lower():
        print(m.group(1), m.group(2))

print("---- chunk file template ----")
for m in re.finditer(r'"?js/"\+[^;]{0,200}', t):
    print(m.group(0)[:260])
    break
