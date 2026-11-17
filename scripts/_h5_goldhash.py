# -*- coding: utf-8 -*-
import io
import os
import re

t = io.open(os.path.join(os.environ["TEMP"], "recharge_app.js"), encoding="utf-8", errors="ignore").read()
for key in ("user_buyGold", "buyGold", "user_goldList", "goldDetail", "user_newCardBind"):
    print(key, [m.group(1) for m in re.finditer(key + r'[":,]+([0-9a-f]{8})', t)])
