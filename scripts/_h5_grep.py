# -*- coding: utf-8 -*-
"""在 H5 bundle 里定位"充值"相关代码。"""
import io
import os
import re
import sys

p = os.path.join(os.environ.get("TEMP", "."), "recharge_app.js")
t = io.open(p, encoding="utf-8", errors="ignore").read()

kw = sys.argv[1] if len(sys.argv) > 1 else "充值"
span = int(sys.argv[2]) if len(sys.argv) > 2 else 200
hits = [m.start() for m in re.finditer(kw, t)]
print("hits:", len(hits))
for i in hits[:20]:
    print("---")
    print(t[max(0, i - span):i + span].replace("\n", " "))
