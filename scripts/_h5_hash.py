# -*- coding: utf-8 -*-
import io
import os
import re

t = io.open(os.path.join(os.environ["TEMP"], "recharge_app.js"), encoding="utf-8", errors="ignore").read()
for key in ("pages_balanceDetail", "pages_walletList", "pages_walletDetail", "operatorInfo", "pages_integral"):
    for m in re.finditer(key + r'[":]+([0-9a-f]{8})', t):
        print(key, m.group(1))
