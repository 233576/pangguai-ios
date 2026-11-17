import io

base = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources'

# ---------- Models.swift：修正 orderStatus 映射 ----------
p = base + r'\Core\Models.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    var statusText: String {
        switch status {
        case 0: return "待支付"
        case 1: return "已支付"
        case 2: return "进行中"
        case 3: return "已完成"
        case 4: return "已取消"
        case 5: return "退款中"
        case 6: return "已退款"
        default: return "状态 \\(status)"
        }
    }

    var isUnpaid: Bool { status == 0 }'''

new = '''    /// 服务端 `orderStatus` 的真实取值（对齐 wash 项目 `getOrderStatus()`）：
    /// 0 待支付 / 1 订单超时 / 2 已支付 / 3 已完成。之前按「1=已支付」写成 4 档，
    /// 会把超时未付的单子当成已支付去倒计时，这是错的。
    var statusText: String {
        switch status {
        case 0: return "待支付"
        case 1: return "已超时"
        case 2: return "已支付"
        case 3: return "已完成"
        case 4: return "已取消"
        case 5: return "退款中"
        case 6: return "已退款"
        default: return "状态 \\(status)"
        }
    }

    var isUnpaid: Bool { status == 0 }

    /// 只有「已支付」才是真的在洗（洗衣机是先付款后启动）。
    var isPaid: Bool { status == 2 }'''

assert old in t
t = t.replace(old, new, 1)

old2 = '''    /// 只有「已支付 / 进行中」且还没到点，才算正在洗。
    func isRunning(now: Date = Date()) -> Bool {
        guard status == 1 || status == 2, let end = endsAt else { return false }
        return end > now
    }'''
new2 = '''    /// 只有「已支付」（2）且还没到点，才算正在洗。
    func isRunning(now: Date = Date()) -> Bool {
        guard status == 2, let end = endsAt else { return false }
        return end > now
    }'''
assert old2 in t
t = t.replace(old2, new2, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('Models patched')

# ---------- AppStore.swift ----------
p = base + r'\Core\AppStore.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    /// 最近一笔已支付/进行中的订单，倒计时结束后用来显示「洗好了」。
    var latestPaidOrder: PGOrder? {
        orders.first { $0.status == 1 || $0.status == 2 }
    }'''
new = '''    /// 最近一笔已支付的订单，倒计时结束后用来显示「洗好了」。
    var latestPaidOrder: PGOrder? {
        orders.first { $0.isPaid }
    }'''
assert old in t
t = t.replace(old, new, 1)

old2 = '''        for order in orders where order.status == 1 || order.status == 2 {'''
new2 = '''        for order in orders where order.isPaid {'''
assert old2 in t
t = t.replace(old2, new2, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('AppStore patched')

# ---------- OrdersView.swift：颜色映射 + 原始状态码 ----------
p = base + r'\Views\OrdersView.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 0: return Flat.orange
        case 1, 2: return Flat.accent
        case 3: return Flat.green
        case 4: return Flat.textTertiary
        case 5, 6: return Flat.purple
        default: return Flat.textSecondary
        }
    }'''
new = '''    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 0: return Flat.orange
        case 1: return Flat.textTertiary
        case 2: return Flat.accent
        case 3: return Flat.green
        case 4: return Flat.textTertiary
        case 5, 6: return Flat.purple
        default: return Flat.textSecondary
        }
    }'''
assert old in t
t = t.replace(old, new, 1)

old2 = '''                    Text(order.createTime.isEmpty ? order.orderNo : order.createTime)
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)'''
new2 = '''                    Text(subtitle(order))
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)'''
assert old2 in t
t = t.replace(old2, new2, 1)

old3 = '''    private func statusColor(_ status: Int) -> Color {'''
new3 = '''    /// 时间 + 订单号 + 原始状态码，方便对着服务端核状态。
    private func subtitle(_ order: PGOrder) -> String {
        var parts: [String] = []
        if !order.createTime.isEmpty { parts.append(order.createTime) }
        if !order.orderNo.isEmpty { parts.append(order.orderNo) }
        parts.append("#\\(order.status)")
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ status: Int) -> Color {'''
assert old3 in t
t = t.replace(old3, new3, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('OrdersView patched')
