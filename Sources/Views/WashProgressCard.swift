import SwiftUI

/// 正在洗涤的倒计时卡片。
///
/// 数据只来自 `/order/list` 的 `createTime` + `markMinutes`（官方没有「剩余时间」接口），
/// 每秒由 `AppStore.now` 驱动重算，进程被杀、App 退到后台再回来都能接上。
struct WashProgressCard: View {
    var order: PGOrder
    var now: Date
    var alert: DeviceAlert? = nil

    private var remaining: TimeInterval { order.remaining(now: now) }
    private var isDone: Bool { remaining <= 0 }
    private var tint: Color { isDone ? Flat.green : Flat.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let alert {
                alertBar(alert)
            }

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

    /// 「设备异常，已暂停」这类服务端提示，样式比照官方 App 顶部那条蓝色横幅。
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

    private var subtitle: String {
        var parts: [String] = []
        if !order.functionName.isEmpty { parts.append(order.functionName) }
        if !order.title.isEmpty { parts.append(order.title) }
        if !order.shopName.isEmpty { parts.append(order.shopName) }
        return parts.isEmpty ? "洗衣机" : parts.joined(separator: " · ")
    }
}
