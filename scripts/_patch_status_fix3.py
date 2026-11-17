import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Core\Models.swift'
t = io.open(p, encoding='utf-8').read()

# 1) 把误插到 PGBalanceItem 里的两块搬走
bad = '''    /// 实付金额（`payPrice` 优先，没有就用标价）。用来判断「这笔到底付没付钱」。
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

'''
assert bad in t
t = t.replace(bad, '', 1)

# 2) 插到 PGOrder 内部（在其 amountText 之前，PGOrder 是唯一带 payPrice 的 struct）
anchor = '''    var amountText: String {
        if !payPrice.isEmpty { return "¥\\(payPrice)" }'''
assert anchor in t

good = '''    /// 实付金额（`payPrice` 优先，没有就用标价）。用来判断「这笔到底付没付钱」。
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

''' + anchor

t = t.replace(anchor, good, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('moved into PGOrder')
