# -*- coding: utf-8 -*-
"""在 myWallet 页面 chunk 里找充值入口与接口。"""
import io
import os
import re

for h in ("2381003c", "785b1c26"):
    p = os.path.join(os.environ["TEMP"], "myWallet_%s.js" % h)
    t = io.open(p, encoding="utf-8", errors="ignore").read()
    print("=====", h, len(t))
    for kw in ("充值", "recharge", "balance", "url:", "operatorId"):
        for m in list(re.finditer(kw, t))[:3]:
            i = m.start()
            print("  [%s]" % kw, t[max(0, i - 150):i + 150].replace("\n", " "))
