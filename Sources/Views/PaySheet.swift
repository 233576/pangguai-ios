import SwiftUI
import UIKit

/// 余额支付面板。
///
/// 这个平台的洗衣机只走余额扣款（`/pay/unify/pay`）：`/pay/unify/prePay` 对 13 / 32
/// 只会回 `payTypeList:[2]` 和空支付串，所以这里既没有二维码，也没有渠道切换，
/// 只有「余额够不够」和「余额不够去哪里充」。
struct PaySheet: View {
    let payment: PendingPayment

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var paying = false
    @State private var alertMessage: String?
    @State private var showingRecharge = false

    private var current: PendingPayment { store.pending ?? payment }
    private var balanceText: String {
        let text = store.user?.balanceText ?? ""
        return text.isEmpty ? "—" : text
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        amountCard
                        balanceCard
                        infoCard
                        actionList
                        footnote
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("余额支付")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Flat.textSecondary)
                }
            }
            .sheet(isPresented: $showingRecharge) {
                RechargeView().environmentObject(store)
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 卡片

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("待支付")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Flat.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Flat.textSecondary)
                Text(current.price.isEmpty ? "0.00" : current.price)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Flat.textPrimary)
                Spacer()
            }

            Text(current.skuName.isEmpty ? current.machineName : current.skuName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Flat.textPrimary)

            Text(current.machineName)
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flatCard()
    }

    private var balanceCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Flat.orange.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Flat.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("账户余额")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
                Text("¥ \(balanceText)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Flat.textPrimary)
            }

            Spacer()

            Button {
                showingRecharge = true
            } label: {
                Text("去充值")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Flat.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Flat.orange.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .flatCard()
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("订单号", current.orderId, mono: true)
            FlatDivider(inset: 14)
            infoRow("网点", current.orgName.isEmpty ? "—" : current.orgName)
            FlatDivider(inset: 14)
            infoRow("支付方式", "余额支付")
        }
        .padding(.vertical, 2)
        .flatCard(fill: Flat.surfaceLow)
    }

    private func infoRow(_ title: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Flat.textTertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium,
                              design: mono ? .monospaced : .default))
                .foregroundStyle(Flat.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var actionList: some View {
        VStack(spacing: 10) {
            Button {
                Task { await pay() }
            } label: {
                HStack(spacing: 8) {
                    if paying {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text(paying ? "支付中…" : "立即用余额支付")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 50))
            .disabled(paying)

            HStack(spacing: 10) {
                Button("余额不足，去充值") { showingRecharge = true }
                    .buttonStyle(FlatButtonStyle(tint: Flat.orange, filled: false, height: 44))

                Button("撤销订单") {
                    Task { await cancelOrder() }
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.red, filled: false, height: 44))
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("一次点击完成扣款，成功后洗衣机立即启动，不需要扫码。")
            Text("余额在官方 App / 充值页里充值，本 App 只是把同一笔余额花出去。")
        }
        .font(.system(size: 12))
        .foregroundStyle(Flat.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - 动作

    private func pay() async {
        guard !paying else { return }
        paying = true
        let error = await store.payWithWallet()
        paying = false
        if let error = error {
            alertMessage = error
        } else {
            dismiss()
        }
    }

    private func cancelOrder() async {
        guard !paying else { return }
        paying = true
        await store.cancelPending()
        paying = false
        dismiss()
    }
}
