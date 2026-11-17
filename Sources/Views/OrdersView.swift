import SwiftUI

/// 订单页：查历史、查支付状态、撤销未启动的订单。
struct OrdersView: View {
    @EnvironmentObject private var store: AppStore

    @State private var cancelling: PGOrder?

    var body: some View {
        ZStack {
            FlatBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header

                    if let pending = store.pending {
                        pendingCard(pending)
                    }

                    if store.orders.isEmpty {
                        emptyCard
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.orders) { order in
                                orderCard(order)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 108)
            }
            .refreshable {
                await store.refreshOrders()
            }
        }
        .confirmationDialog(
            cancelling.map { "撤销订单 \($0.orderNo.isEmpty ? $0.id : $0.orderNo)？" } ?? "",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible
        ) {
            if let order = cancelling {
                Button("撤销这笔订单", role: .destructive) {
                    let target = order
                    cancelling = nil
                    Task { await store.cancel(order: target) }
                }
                Button("算了", role: .cancel) { cancelling = nil }
            }
        } message: {
            Text("未启动的订单可以撤销，已经出水的撤销不掉。")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("订单")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Flat.textPrimary)
                Text(store.loggedIn ? "共 \(store.orders.count) 条" : "登录后可查看")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
            }
            Spacer()
            Button {
                Task { await store.refreshOrders() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Flat.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Flat.surfaceHigh)
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
        }
        .padding(.top, 12)
    }

    private func pendingCard(_ pending: PendingPayment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Flat.orange)
                Text("待支付")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Flat.textPrimary)
                Spacer()
                Text(pending.price.isEmpty ? "—" : "¥\(pending.price)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Flat.orange)
            }
            Text(pending.machineName.isEmpty ? pending.orderId : pending.machineName)
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
            HStack(spacing: 10) {
                Button {
                    Task { await store.checkPendingPayment() }
                } label: {
                    Text("我付好了")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.orange, filled: true, height: 44))

                Button {
                    Task { await store.cancelPending() }
                } label: {
                    Text("撤销")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.red, filled: false, height: 44))
            }
        }
        .padding(16)
        .flatCard(fill: Flat.orange.opacity(0.08))
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Flat.textTertiary)
            Text(store.loggedIn ? "还没有订单记录" : "登录后才能看订单")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Flat.textSecondary)
            Text("在洗衣页扫码下单后，这里会出现记录。")
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .flatCard(fill: Flat.surfaceLow)
    }

    private func orderCard(_ order: PGOrder) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(order.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text(order.createTime.isEmpty ? order.orderNo : order.createTime)
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)
                }
                Spacer()
                Text(order.statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(order.status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .flatPill(selected: true, tint: statusColor(order.status))
            }

            if order.isRunning(now: store.now) {
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
            }

            if order.isUnpaid {
                Button {
                    cancelling = order
                } label: {
                    Text("撤销订单")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.red, filled: false, height: 40))
            }
        }
        .padding(14)
        .flatCard()
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 0: return Flat.orange
        case 1, 2: return Flat.accent
        case 3: return Flat.green
        case 4: return Flat.textTertiary
        case 5, 6: return Flat.purple
        default: return Flat.textSecondary
        }
    }
}
