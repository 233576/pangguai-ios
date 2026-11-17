import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\OrdersView.swift'
t = io.open(p, encoding='utf-8').read()

old = '''            HStack(spacing: 10) {
                Text(order.amountText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Flat.textPrimary)
                if !order.shopName.isEmpty {
                    Text(order.shopName)
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }'''

new = '''            if order.isRunning(now: store.now) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(order.remainingText(now: store.now))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Flat.accent)
                        Text("后洗好")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.textSecondary)
                        Spacer(minLength: 0)
                        Text(order.finishText(now: store.now))
                            .font(.system(size: 11))
                            .foregroundStyle(Flat.textTertiary)
                    }
                    FlatProgressBar(progress: order.progress(now: store.now),
                                    tint: Flat.accent,
                                    height: 6)
                }
            }

            HStack(spacing: 10) {
                Text(order.amountText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Flat.textPrimary)
                if !order.shopName.isEmpty {
                    Text(order.shopName)
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }'''

assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('OrdersView patched')

# ---------- 时钟启停：AppShell 里负责 ----------
p2 = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\AppShell.swift'
s = io.open(p2, encoding='utf-8').read()
print('---- AppShell ----')
print(s[:1800])
