import SwiftUI

/// 正在洗涤的倒计时卡片。
///
/// 数据只来自 `/order/list` 的 `createTime` + `markMinutes`（官方没有「剩余时间」接口），
/// 每秒由 `AppStore.now` 驱动重算，进程被杀、App 退到后台再回来都能接上。
struct WashProgressCard: View {
    var order: PGOrder
    var now: Date

    private var remaining: TimeInterval { order.remaining(now: now) }
    private var isDone: Bool { remaining <= 0 }
    private var tint: Color { isDone ? Flat.green : Flat.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FlatStatusMark(symbol: isDone ? "checkmark" : "drop.fill", tint: tint, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isDone ? "洗好了" : "正在洗涤")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Flat.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(order.minutes) 分钟")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Flat.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(order.remainingText(now: now))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isDone ? Flat.green : Flat.textPrimary)
                Text(isDone ? "已完成" : "后洗好")
                    .font(.subheadline)
                    .foregroundStyle(Flat.textSecondary)
                Spacer(minLength: 0)
                Text(order.finishText(now: now))
                    .font(.footnote)
                    .foregroundStyle(Flat.textTertiary)
            }

            FlatProgressBar(progress: order.progress(now: now), tint: tint, height: 8)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(order.createTime.isEmpty ? "—" : "开始于 \(order.createTime)")
                    .font(.caption2)
                Spacer(minLength: 0)
                if !order.orderNo.isEmpty {
                    Text(order.orderNo)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Flat.textTertiary)
        }
        .padding(18)
        .flatCard()
    }

    private var subtitle: String {
        var parts: [String] = []
        if !order.functionName.isEmpty { parts.append(order.functionName) }
        if !order.title.isEmpty { parts.append(order.title) }
        if !order.shopName.isEmpty { parts.append(order.shopName) }
        return parts.isEmpty ? "洗衣机" : parts.joined(separator: " · ")
    }
}
