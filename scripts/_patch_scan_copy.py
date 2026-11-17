import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\ScanSheet.swift'
t = io.open(p, encoding='utf-8').read()

pairs = [
    ('/// 扫码取机器码：支付宝/微信扫到的是 `NQT=...` 链接或纯码，都会交给 onCode。',
     '/// 扫码取机器码：官方二维码是 `https://h5.qiekj.com/skip?...&NQT=...`，也可能是 `NQT=...` 或纯码，都会交给 onCode。'),
    ('TextField("手动输入机器码（如 NQT…）", text: $manual)',
     'TextField("机器码或二维码链接（NQT=…）", text: $manual)'),
]
for old, new in pairs:
    if old in t:
        t = t.replace(old, new)
        print('replaced:', old[:40])
    else:
        print('MISS:', old[:40])

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('written')
