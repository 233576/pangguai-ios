# -*- coding: utf-8 -*-
import io
import os

t = io.open(os.path.join(os.environ["TEMP"], "recharge_app.js"), encoding="utf-8", errors="ignore").read()
i = t.find('"js/"+(')
print(t[i:i + 1500])
