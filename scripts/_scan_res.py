# -*- coding: utf-8 -*-
"""扫 resources.arsc，找和充值/余额相关的字符串资源名。"""
import re
import sys
import zipfile

apk = sys.argv[1]
with zipfile.ZipFile(apk) as z:
    data = z.read("resources.arsc")
txt = data.decode("utf-16-le", "ignore") + "\n" + data.decode("latin-1", "ignore")
for kw in ("充值", "余额", "钱包"):
    hits = 0
    for m in re.finditer(kw, txt):
        i = m.start()
        seg = txt[max(0, i - 40):i + 40].replace("\x00", "|")
        seg = "".join(ch if ch.isprintable() else "|" for ch in seg)
        print(kw, "|", seg)
        hits += 1
        if hits >= 12:
            break
