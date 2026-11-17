# -*- coding: utf-8 -*-
"""在 balanceDetail / operatorInfo chunk 里找充值按钮与接口调用。"""
import io
import os
import re
import sys

files = sys.argv[1:]
for p in files:
    t = io.open(p, encoding="utf-8", errors="ignore").read()
    print("=====", os.path.basename(p), len(t))
    for kw in ("充值", "recharge", "charge", "url", "operator"):
        hits = list(re.finditer(kw, t))[:3]
        for m in hits:
            i = m.start()
            print("  [%s]" % kw, t[max(0, i - 180):i + 180].replace("\n", " "))
