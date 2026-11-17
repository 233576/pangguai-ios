import SwiftUI
import UIKit
import WebKit

/// 支付面板：微信 / 支付宝 / 余额，三个渠道都能在同一笔订单上切换（订单号不变）。
///
/// - 微信：拿 `prepayParam`，可能是 `mweb_url`（走应用内网页，网页里会自己唤起微信）、
///   `code_url`（画二维码）、`weixin://`（直接 open），也可能是 App 支付参数（没有 SDK 调不起来，只能提示）。
/// - 支付宝：拼 `alipays://platformapi/startapp?appId=20000125&orderSuffix=…`，同时出二维码。
/// - 余额：`/pay/unify/pay` 当场扣款。
struct PaySheet: View {
    let payment: PendingPayment

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var paying = false
    @State private var switching = false
    @State private var alertMessage: String?
    @State private var showingRecharge = false
    @State private var showingWebPay = false
    @State private var webPayURL: URL?
    @State private var showRaw = false
    @State private var showParam = false

    private var current: PendingPayment { store.pending ?? payment }
    private var payType: Int { current.payType }
    private var handoff: PGProtocol.PayHandoff {
        PGProtocol.handoff(param: current.prepayParam, payType: payType)
    }
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
                        channelPicker
                        payArea
                        balanceCard
                        infoCard
                        actionList
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(PGProtocol.payTitle(payType))
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
            .sheet(isPresented: $showingWebPay) {
                if let url = webPayURL {
                    PayWebView(url: url) { showingWebPay = false }
                        .environmentObject(store)
                }
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

    private var channelPicker: some View {
        HStack(spacing: 8) {
            chip("微信支付", tint: Flat.green, type: PGProtocol.payTypeWeChat)
            chip("支付宝", tint: Flat.accent, type: PGProtocol.payTypeAlipay)
            chip("余额", tint: Flat.orange, type: PGProtocol.payTypeWallet)
        }
    }

    private func chip(_ title: String, tint: Color, type: Int) -> some View {
        Button {
            guard current.payType != type, !switching else { return }
            Task { await switchTo(type) }
        } label: {
            HStack(spacing: 5) {
                if switching && current.payType != type {
                    ProgressView().tint(tint).scaleEffect(0.6)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(current.payType == type ? tint : Flat.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Flat.controlRadius, style: .continuous)
                .fill(current.payType == type ? tint.opacity(0.16) : Flat.surfaceHigh)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Flat.controlRadius, style: .continuous)
                .strokeBorder(current.payType == type ? tint.opacity(0.55) : Flat.stroke, lineWidth: 1)
        )
        .disabled(switching)
    }

    @ViewBuilder
    private var payArea: some View {
        if payType == PGProtocol.payTypeWallet {
            EmptyView()
        } else if current.prepayParam.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("没有拿到支付串")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Flat.textPrimary)
                Text(store.lastPrepayError ?? "点下面的「重新取支付串」再试一次。")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .flatCard(fill: Flat.surfaceLow)
        } else {
            VStack(spacing: 12) {
                if let text = handoff.qr, handoff.showQR {
                    QRCodeView(text: text, size: 208)
                        .padding(.top, 4)
                    Text(payType == PGProtocol.payTypeWeChat
                         ? "用微信「扫一扫」扫这个码付款（也可以截屏后用相册识别）"
                         : "用支付宝「扫一扫」扫这个码付款")
                        .font(.system(size: 12))
                        .foregroundStyle(Flat.textTertiary)
                        .multilineTextAlignment(.center)
                }

                if !handoff.note.isEmpty {
                    Text(handoff.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .flatCard()
        }
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
                Text("账号余额")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
                Text("¥ \(balanceText)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Flat.textPrimary)
                Text("店铺余额 \(store.shopBalanceText)")
                    .font(.system(size: 11))
                    .foregroundStyle(store.shopBalanceTotal > 0 ? Flat.green : Flat.textTertiary)
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
            infoRow("支付方式", PGProtocol.payTitle(payType))
            FlatDivider(inset: 14)
            infoRow("支付串", current.prepayParam.isEmpty
                    ? "空（点重新取支付串）"
                    : "\(current.prepayParam.count) 字符")
            if !current.prepayParam.isEmpty {
                FlatDivider(inset: 14)
                Button {
                    showParam.toggle()
                } label: {
                    HStack {
                        Text(showParam ? "收起支付串" : "查看支付串全文")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.accent)
                        Spacer()
                        Image(systemName: showParam ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Flat.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if showParam {
                    Text(current.prepayParam)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Flat.textTertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            if !store.lastPrepayRaw.isEmpty {
                FlatDivider(inset: 14)
                Button {
                    showRaw.toggle()
                } label: {
                    HStack {
                        Text(showRaw ? "收起原始响应" : "查看原始响应")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.accent)
                        Spacer()
                        Image(systemName: showRaw ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Flat.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if showRaw {
                    Text(store.lastPrepayRaw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Flat.textTertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
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
            if payType == PGProtocol.payTypeWallet {
                Button {
                    Task { await payWithWallet() }
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
            } else {
                Button {
                    openPayTarget()
                } label: {
                    Text("打开\(PGProtocol.payTitle(payType))付款")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(FlatButtonStyle(
                    tint: payType == PGProtocol.payTypeWeChat ? Flat.green : Flat.accent,
                    filled: true, height: 50))
                .disabled(switching)

                Button {
                    UIPasteboard.general.string = current.prepayParam
                    alertMessage = "支付串已复制（\(current.prepayParam.count) 字符）"
                } label: {
                    Text("复制支付串")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.textSecondary, filled: false, height: 46))
            }

            Button {
                Task { await refreshStatus() }
            } label: {
                Text("我付好了，查状态")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.green, filled: false, height: 46))

            HStack(spacing: 10) {
                Button("重新取支付串") {
                    Task { await reprepare() }
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 44))

                Button("撤销订单") {
                    Task { await cancelOrder() }
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.red, filled: false, height: 44))
            }
        }
    }

    // MARK: - 动作

    private func switchTo(_ type: Int) async {
        switching = true
        let error = await store.switchPayType(type)
        switching = false
        if let error = error {
            alertMessage = error
        } else if store.pending == nil {
            dismiss()
        }
    }

    private func openPayTarget() {
        let plan = handoff
        if !plan.schemes.isEmpty {
            openSchemes(plan.schemes, index: 0)
            return
        }
        if let web = plan.web {
            webPayURL = web
            showingWebPay = true
            return
        }
        if plan.isWechatAppParam {
            UIPasteboard.general.string = current.prepayParam
            alertMessage = "这是微信 App 支付参数，weixin://wap/pay 没被系统接受。参数已复制到剪贴板，"
                + "可以换余额、换支付宝，或者用另一台手机扫二维码。"
            return
        }
        alertMessage = "没有可用的跳转方式，先用另一台手机扫码吧"
    }

    /// 依次尝试多个 scheme（微信 wap/pay 有几种字段组合，能通一种就够）。
    private func openSchemes(_ urls: [URL], index: Int) {
        guard index < urls.count else {
            UIPasteboard.general.string = current.prepayParam
            alertMessage = "系统没有接受任何一个\(PGProtocol.payTitle(payType))跳转链接。"
                + "支付串已复制到剪贴板；也可以换渠道，或用另一台手机扫码。"
            return
        }
        let url = urls[index]
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok {
                Task { @MainActor in
                    openSchemes(urls, index: index + 1)
                }
            }
        }
    }

    private func payWithWallet() async {
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

    private func reprepare() async {
        switching = true
        await store.reopenPrepay()
        switching = false
        if let error = store.lastPrepayError {
            alertMessage = error
        }
    }

    private func refreshStatus() async {
        switching = true
        let paid = await store.checkPendingPayment()
        switching = false
        if paid {
            dismiss()
        } else {
            alertMessage = "还没查到付款成功。等几秒再点一次，或者去「订单」页看一下。"
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

/// 应用内打开的支付网页（微信 H5 支付 / 支付宝网页版都在这里跑）。
private struct PayWebView: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor(Flat.background)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        web.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            web.topAnchor.constraint(equalTo: controller.view.topAnchor),
            web.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])
        web.load(URLRequest(url: url))

        let nav = UINavigationController(rootViewController: controller)
        controller.navigationItem.title = "付款"
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "关闭", style: .plain, target: context.coordinator,
            action: #selector(Coordinator.close))
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        @objc func close() { onClose() }
    }
}
