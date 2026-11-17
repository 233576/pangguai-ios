# -*- coding: utf-8 -*-
"""打印 buyGold chunk 的 methods 区，看它调哪些接口、传什么参数。"""
import io
import os
import re

t = io.open(os.path.join(os.environ["TEMP"], "user_buyGold.js"), encoding="utf-8", errors="ignore").read()
for m in re.finditer(r'\$(?:post|get)\("[^"]+"', t):
    print(m.group(0))
print("---- tokenCoin / operator refs ----")
for kw in ("operatorId", "shopId", "orgId", "goodsId"):
    for m in list(re.finditer(kw, t))[:4]:
        i = m.start()
        print(kw, "|", t[max(0, i - 120):i + 120].replace("\n", " "))
