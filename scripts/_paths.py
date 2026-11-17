# -*- coding: utf-8 -*-
"""枚举 APK dex 里所有形如 a/b/c 的接口路径，筛出和钱相关的。"""
import re
import sys
import zipfile

apk = sys.argv[1]
pat = re.compile(rb"[a-z][a-zA-Z0-9_]*(?:/[a-zA-Z0-9_]+){1,4}")
keep = ("charge", "balance", "gold", "ticket", "wallet", "money", "recharge", "account")

seen = set()
with zipfile.ZipFile(apk) as z:
    for name in z.namelist():
        if not (name.startswith("classes") and name.endswith(".dex")):
            continue
        data = z.read(name)
        for m in pat.finditer(data):
            s = m.group(0).decode("ascii", "ignore")
            if any(k in s for k in keep) and s not in seen:
                seen.add(s)
                print(name, s)
