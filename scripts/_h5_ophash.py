# -*- coding: utf-8 -*-
import io
import os
import re

t = io.open(os.path.join(os.environ["TEMP"], "recharge_app.js"), encoding="utf-8", errors="ignore").read()
for key in ("user_operatorInfo", "operatorInfo", "user_recharge"):
    for m in re.finditer(key + r'[":,]+([0-9a-f]{8})', t):
        print(key, m.group(1))
print("--- occurrences ---")
for m in list(re.finditer("user_operatorInfo", t))[:6]:
    i = m.start()
    print(t[max(0, i - 200):i + 200])
    print()
