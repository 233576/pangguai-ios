import io

base = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources'

# ---------- LaundryView：把倒计时卡插到账号卡下面 ----------
p = base + r'\Views\LaundryView.swift'
t = io.open(p, encoding='utf-8').read()

old = '''                    header
                    accountCard
                    scanCard
'''
new = '''                    header
                    accountCard

                    if let running = store.runningOrder {
                        WashProgressCard(order: running, now: store.now)
                    } else if let paid = store.latestPaidOrder,
                              let end = paid.endsAt,
                              end.timeIntervalSince(store.now) > -300 {
                        WashProgressCard(order: paid, now: store.now)
                    }

                    scanCard
'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('LaundryView patched')

# ---------- OrdersView：订单行显示倒计时 ----------
p = base + r'\Views\OrdersView.swift'
t = io.open(p, encoding='utf-8').read()
print('---- OrdersView row ----')
i = t.find('struct OrderRow')
if i < 0:
    i = t.find('private func row')
print(t[i:i+2200])
