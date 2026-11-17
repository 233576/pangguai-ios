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

/// 待支付面板：扫码付款，或者直接拉起支付宝。
struct PaySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var payment: PendingPayment

    @State private var checking = false
    @State private var cancelling = false

    private var qrText: String {
        PGProtocol.qrContent(for: payment.prepayParam)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text(payment.price.isEmpty ? "待支付" : "¥\(payment.price)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Flat.textPrimary)
                            Text(payment.machineName.isEmpty ? payment.orderId : payment.machineName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Flat.textSecondary)
                            if !payment.skuName.isEmpty {
                                Text(payment.skuName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Flat.textTertiary)
                            }
                        }
                        .padding(.top, 8)

                        if payment.hasQR {
                            VStack(spacing: 12) {
                                QRCodeView(text: qrText, size: 230)
                                Text("用支付宝「扫一扫」这张码，或点下面的按钮直接跳转。")
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Flat.textTertiary)
                                    .padding(.horizontal, 20)
                            }
                            .padding(16)
                            .flatCard()
                        } else {
                            VStack(spacing: 10) {
                                Text("这笔订单还没拿到支付串")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Flat.textPrimary)
                                Text("点「重新取支付串」再试一次，订单号 \(payment.orderId)")
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
                            openAlipay()
                        } label: {
                            Text("打开支付宝付款")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 50))
                        .disabled(!payment.hasQR)

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
                            row("订单号", payment.orderId)
                            if !payment.orgName.isEmpty { row("网点", payment.orgName) }
                            row("创建时间", Self.formatter.string(from: payment.createdAt))
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

    private func openAlipay() {
        let candidates = PGProtocol.paymentCandidates(for: payment.prepayParam)
        openNext(candidates, index: 0)
    }

    private func openNext(_ urls: [URL], index: Int) {
        guard index < urls.count else {
            store.errorMessage = "没能拉起支付宝，请用另一台手机扫上面的二维码"
            return
        }
        let url = urls[index]
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok {
                openNext(urls, index: index + 1)
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
