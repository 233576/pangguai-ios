# -*- coding: utf-8 -*-
"""扫描全部 dex，找含"充值"的中文串（判断是否漏了入口）。"""
import io
import re
import sys
import zipfile

apk = sys.argv[1]
with zipfile.ZipFile(apk) as z:
    for name in z.namelist():
        if not (name.startswith("classes") and name.endswith(".dex")):
            continue
        data = z.read(name)
        txt = data.decode("utf-8", "ignore")
        for m in re.finditer("充值", txt):
            i = m.start()
            seg = txt[max(0, i - 24):i + 24].replace("\x00", "|")
            seg = "".join(ch if ch.isprintable() else "|" for ch in seg)
            print(name, "|", seg)
