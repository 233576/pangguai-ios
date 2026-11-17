# -*- coding: utf-8 -*-
"""找出 toString 同时含 orgId 与 operatorId 的实体类（用 dex 原始串邻近关系粗判）。"""
import struct
import sys
import zipfile

apk = sys.argv[1]
want = ["orgId=", "operatorId=", "orgName="]

with zipfile.ZipFile(apk) as z:
    names = [n for n in z.namelist() if n.startswith("classes") and n.endswith(".dex")]
    for name in names:
        data = z.read(name)
        # 只在 classes11 里做：把整段当字节找邻近
        text = data.decode("latin-1")
        for w in want:
            pass
        i = 0
        hits = 0
        while True:
            j = text.find("operatorId=", i)
            if j < 0:
                break
            window = text[max(0, j - 4000):j + 4000]
            if "orgId=" in window and "orgName=" in window:
                # 找最近的类名
                k = window.rfind("Lcom/qiekj")
                seg = window[k:k + 120] if k >= 0 else "?"
                print(name, "near:", seg.split("\x00")[0])
                hits += 1
                if hits > 6:
                    break
            i = j + 1
