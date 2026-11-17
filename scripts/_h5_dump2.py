# -*- coding: utf-8 -*-
import io
import os
import re

t = io.open(os.path.join(os.environ["TEMP"], "recharge_app.js"), encoding="utf-8", errors="ignore").read()
for m in re.finditer(r'pages_myWallet', t):
    i = m.start()
    print("=== at", i)
    print(t[max(0, i - 220):i + 220])
    print()
