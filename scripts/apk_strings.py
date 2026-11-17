import re
import sys
import zipfile

APK = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\Chen\AppData\Local\Temp\pg.apk'

PATTERNS = [
    rb'/goods/scan[^\x00-\x1f"\']{0,40}',
    rb'/goods/[a-zA-Z0-9_/]{2,40}',
    rb'appSecret[^\x00-\x1f]{0,80}',
    rb'/goods/normal/[a-zA-Z0-9_/]{2,40}',
    rb'/machine/[a-zA-Z0-9_/]{2,40}',
    rb'/device/[a-zA-Z0-9_/]{2,40}',
    rb'/qr[a-zA-Z0-9_/]{0,30}',
]

with zipfile.ZipFile(APK) as zf:
    names = [n for n in zf.namelist() if n.endswith('.dex') or n.endswith('.so') or n.endswith('.json')]
    print('scan entries:', len(names))
    hits = {}
    for name in names:
        blob = zf.read(name)
        for pattern in PATTERNS:
            for match in re.finditer(pattern, blob):
                text = match.group(0).decode('utf-8', 'replace')
                hits.setdefault(text, set()).add(name)
    goods = sorted(k for k in hits if k.startswith('/goods'))
    print('== /goods* 路径 (%d) ==' % len(goods))
    for k in goods:
        print(' ', k)
    other = sorted(k for k in hits if not k.startswith('/goods'))
    print('== 其它 (%d) ==' % len(other))
    for k in other[:60]:
        print(' ', k)
