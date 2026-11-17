# -*- coding: utf-8 -*-
import io
import os

t = io.open(os.path.join(os.environ["TEMP"], "user_buyGold.js"), encoding="utf-8", errors="ignore").read()
i = t.find("getTokenCoinGoods")
print(t[i - 200:i + 1200])
