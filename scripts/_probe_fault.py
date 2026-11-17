"""找「设备异常 / 已暂停 / 门没关紧」这类提示在 APK 里的出处与字段名。

做法：在 dex 里按 UTF-8 搜索中文文案，命中后在该偏移附近
dump 可打印 ASCII 串（字段名通常紧挨着文案）。
"""
import re
import sys
import zipfile

APK = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pg\inbox\com.qiekj.user.apk'

WORDS = [
    '设备异常', '已暂停', '请确认洗衣机门', '门是否关紧', '关紧', '故障上报',
    '暂停', '异常', '设备故障', '故障码', '请在', '联系商家',
]

ASCII = re.compile(rb'[\x20-\x7e]{3,}')


def dump_near(blob, pos, span=700):
    lo = max(0, pos - span)
    hi = min(len(blob), pos + span)
    seg = blob[lo:hi]
    out = []
    for m in ASCII.finditer(seg):
        s = m.group().decode('ascii', 'ignore')
        if len(s) >= 3:
            out.append(s)
    return out


def main():
    z = zipfile.ZipFile(APK)
    for name in [n for n in z.namelist() if n.endswith('.dex')]:
        blob = z.read(name)
        hits = {}
        for w in WORDS:
            b = w.encode('utf-8')
            idx = blob.find(b)
            if idx >= 0:
                hits[w] = idx
        if not hits:
            continue
        print('\n===== %s =====' % name)
        for w, idx in hits.items():
            print('\n-- %s @%d --' % (w, idx))
            fields = dump_near(blob, idx)
            # 只打印看起来像字段名/标识符的
            picked = [f for f in fields if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_$.]{2,}', f)]
            print('   ', ' | '.join(picked[:60]))


if __name__ == '__main__':
    main()
