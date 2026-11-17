import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\LaundryView.swift'
t = io.open(p, encoding='utf-8').read()

old = 'Button("支付 \\(sku.priceText)") {'
new = 'Button("用\\(PGProtocol.payTitle(store.settings.payType))付 \\(sku.priceText)") {'
if old in t:
    t = t.replace(old, new)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('patched')
else:
    print('MISS')
    for line in t.split('\n'):
        if 'sku.priceText' in line:
            print(repr(line))
