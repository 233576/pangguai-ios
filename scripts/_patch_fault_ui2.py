import io

base = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources'

# ---------- WashProgressCard：告警条 ----------
p = base + r'\Views\WashProgressCard.swift'
t = io.open(p, encoding='utf-8').read()

old = '''struct WashProgressCard: View {
    var order: PGOrder
    var now: Date
'''
new = '''struct WashProgressCard: View {
    var order: PGOrder
    var now: Date
    var alert: DeviceAlert? = nil
'''
assert old in t
t = t.replace(old, new, 1)

old2 = '''    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {'''
new2 = '''    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let alert {
                alertBar(alert)
            }

            HStack(spacing: 12) {'''
assert old2 in t
t = t.replace(old2, new2, 1)

old3 = '''    private var subtitle: String {'''
new3 = '''    /// 「设备异常，已暂停」这类服务端提示，样式比照官方 App 顶部那条蓝色横幅。
    private func alertBar(_ alert: DeviceAlert) -> some View {
        let tint = alert.isWarning ? Flat.orange : Flat.accent
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Flat.textPrimary)
                Text(alert.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if alert.isWarning {
                    Text("检查洗衣机门是否关紧；仍然异常就联系商家点「故障上报」。")
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var subtitle: String {'''
assert old3 in t
t = t.replace(old3, new3, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('WashProgressCard patched')

# ---------- LaundryView：传 alert ----------
p = base + r'\Views\LaundryView.swift'
t = io.open(p, encoding='utf-8').read()

old = '''                    if let running = store.runningOrder {
                        WashProgressCard(order: running, now: store.now)
                    } else if let paid = store.latestPaidOrder,
                              let end = paid.endsAt,
                              end.timeIntervalSince(store.now) > -300 {
                        WashProgressCard(order: paid, now: store.now)
                    }'''
new = '''                    if let running = store.runningOrder {
                        WashProgressCard(order: running, now: store.now, alert: store.deviceAlert)
                    } else if let paid = store.latestPaidOrder,
                              let end = paid.endsAt,
                              end.timeIntervalSince(store.now) > -300 {
                        WashProgressCard(order: paid, now: store.now, alert: store.deviceAlert)
                    }'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('LaundryView patched')
