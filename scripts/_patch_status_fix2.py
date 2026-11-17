import io

base = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources'

# ---------- Models.swift：支付金额 + 取消/完成判定 ----------
p = base + r'\Core\Models.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    var amountText: String {'''
new = '''    /// 实付金额（`payPrice` 优先，没有就用标价）。用来判断「这笔到底付没付钱」。
    var paidAmount: Double {
        for raw in [payPrice, markPrice] where !raw.isEmpty {
            if let value = Double(raw) { return value }
        }
        return 0
    }

    /// 状态文案的最终版：服务端状态码 + 金额双保险。
    /// 取消掉的订单在部分网点会被回写成 3（已完成），金额是 0，这里纠回「已取消」。
    var displayStatusText: String {
        if status == 3 && paidAmount <= 0 { return "已取消" }
        if status == 2 && paidAmount <= 0 { return "未付款" }
        return statusText
    }

    var amountText: String {'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('Models patched')

# ---------- AppStore.swift：震动只对 24 小时内的单子 ----------
p = base + r'\Core\AppStore.swift'
t = io.open(p, encoding='utf-8').read()

old = '''        for order in orders where order.isPaid {
            guard let end = order.endsAt, end <= now else { continue }'''
new = '''        for order in orders where order.isPaid {
            guard let end = order.endsAt, end <= now else { continue }
            // 只对最近一天的单子响一次，避免打开 App 时被历史订单震到。
            guard now.timeIntervalSince(end) < 24 * 3600 else { continue }'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('AppStore patched')

# ---------- OrdersView.swift：用 displayStatusText ----------
p = base + r'\Views\OrdersView.swift'
t = io.open(p, encoding='utf-8').read()

old = '''                Text(order.statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(order.status))'''
new = '''                Text(order.displayStatusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(order.status))'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('OrdersView patched')
