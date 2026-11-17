import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// 二维码图片。
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 220

    private static let context = CIContext()
    private static let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image = makeImage() {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Flat.surfaceHigh)
                    .frame(width: size, height: size)
                    .overlay(
                        Text("二维码生成失败")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.textTertiary)
                    )
            }
        }
    }

    private func makeImage() -> UIImage? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        Self.filter.message = data
        Self.filter.correctionLevel = "M"
        guard let output = Self.filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = Self.context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 待支付面板：扫码付款，或者直接拉起支付宝 / 微信。
struct PaySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var payment: PendingPayment

    @State private var checking = false
    @State private var cancelling = false
    @State private var payTypeOverride: Int?
    @State private var switching = false

    /// 以 store 里的挂单为准（切换支付方式后 prepayParam / payType 都会变）。
    private var current: PendingPayment { store.pending ?? payment }

    private var payType: Int { payTypeOverride ?? current.payType }

    private var isWeChat: Bool { payType == PGProtocol.payTypeWeChat }

    private var qrText: String {
        PGProtocol.qrContent(for: current.prepayParam, payType: payType)
    }

    private var payLabel: String { PGProtocol.payTitle(payType) }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text(current.price.isEmpty ? "待支付" : "¥\(current.price)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Flat.textPrimary)
                            Text(current.machineName.isEmpty ? current.orderId : current.machineName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Flat.textSecondary)
                            if !current.skuName.isEmpty {
                                Text(current.skuName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Flat.textTertiary)
                            }
                        }
                        .padding(.top, 8)

                        payTypePicker

                        if current.hasQR {
                            VStack(spacing: 12) {
                                QRCodeView(text: qrText, size: 230)
                                Text(isWeChat
                                     ? "用微信「扫一扫」这张码付款；微信 App 支付串在 iOS 上无法直接调起，扫一扫最稳。"
                                     : "用支付宝「扫一扫」这张码，或点下面的按钮直接跳转。")
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Flat.textTertiary)
                                    .padding(.horizontal, 20)
                            }
                            .padding(16)
                            .flatCard()
                        } else {
                            VStack(spacing: 10) {
                                Text("这笔订单还没拿到\(payLabel)支付串")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Flat.textPrimary)
                                Text("点「重新取支付串」再试一次，订单号 \(current.orderId)")
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Flat.textTertiary)
                                Button {
                                    Task { await store.reopenPrepay() }
                                } label: {
                                    Text("重新取支付串")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 46))
                            }
                            .padding(16)
                            .flatCard()
                        }

                        Button {
                            openPayApp()
                        } label: {
                            HStack(spacing: 8) {
                                if switching { ProgressView().tint(.white) }
                                Text("打开\(payLabel)付款")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FlatButtonStyle(tint: isWeChat ? Flat.green : Flat.accent,
                                                      filled: true, height: 50))
                        .disabled(!current.hasQR || switching)

                        Button {
                            UIPasteboard.general.string = qrText
                            store.noticeMessage = "支付链接已复制，可粘贴到\(payLabel)或浏览器打开"
                        } label: {
                            Text("复制支付链接")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FlatButtonStyle(tint: Flat.surfaceHigh, filled: false, height: 44))
                        .disabled(!current.hasQR)

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    checking = true
                                    let paid = await store.checkPendingPayment()
                                    checking = false
                                    if paid { dismiss() }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if checking { ProgressView().tint(Flat.textPrimary) }
                                    Text(checking ? "查询中…" : "我付好了")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FlatButtonStyle(tint: Flat.surfaceHigh, filled: false, height: 46))

                            Button {
                                Task {
                                    cancelling = true
                                    await store.cancelPending()
                                    cancelling = false
                                    dismiss()
                                }
                            } label: {
                                Text("撤销订单")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FlatButtonStyle(tint: Flat.red, filled: false, height: 46))
                            .disabled(cancelling)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            row("订单号", current.orderId)
                            if !current.orgName.isEmpty { row("网点", current.orgName) }
                            row("支付方式", payLabel)
                            row("创建时间", Self.formatter.string(from: current.createdAt))
                        }
                        .padding(16)
                        .flatCard(fill: Flat.surfaceLow)

                        Text("付完款洗衣机才会启动。若长时间没启动，用订单页的「刷新」查一下状态。")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.textTertiary)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("扫码支付")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Flat.accent)
                }
            }
        }
    }

    /// 支付宝 / 微信切换。切换会用同一个订单号重新取支付串，不会多建订单。
    private var payTypePicker: some View {
        HStack(spacing: 10) {
            option(title: "支付宝", detail: "扫码 / 跳转", type: PGProtocol.payTypeAlipay)
            option(title: "微信支付", detail: "扫一扫付款", type: PGProtocol.payTypeWeChat)
        }
    }

    private func option(title: String, detail: String, type: Int) -> some View {
        let selected = payType == type
        return Button {
            guard !switching, payType != type else { return }
            Task {
                switching = true
                await store.switchPayType(type)
                switching = false
                if store.pending?.payType == type {
                    payTypeOverride = type
                }
            }
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Flat.accent : Flat.textSecondary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Flat.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .flatPill(selected: selected, tint: type == PGProtocol.payTypeWeChat ? Flat.green : Flat.accent)
        .disabled(switching)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Flat.textSecondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func openPayApp() {
        let param = current.prepayParam
        let candidates = isWeChat
            ? PGProtocol.wechatCandidates(for: param)
            : PGProtocol.paymentCandidates(for: param)
        if isWeChat, PGProtocol.wechatNeedsNativeApp(param: param) {
            store.log("微信支付串是 App 支付参数（appid/partnerid/prepayid），iOS 无法用 URL 直接调起，改用扫码")
        }
        openNext(candidates, index: 0, payLabel: payLabel)
    }

    private func openNext(_ urls: [URL], index: Int, payLabel: String) {
        guard index < urls.count else {
            store.errorMessage = "系统没让\(payLabel)接管这个链接：请用另一台手机扫上面的二维码，或点「复制支付链接」自己粘贴"
            return
        }
        let url = urls[index]
        let app = UIApplication.shared
        // 先 canOpenURL：没装对应 App 时 iOS 会静默失败，这里提前给出可照做的提示。
        guard app.canOpenURL(url) else {
            openNext(urls, index: index + 1, payLabel: payLabel)
            return
        }
        app.open(url, options: [:]) { ok in
            if !ok {
                openNext(urls, index: index + 1, payLabel: payLabel)
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
