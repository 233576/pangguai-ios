import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// 二维码图片。
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 220

    private static let context = CIContext()

    var body: some View {
        Group {
            if let image = Self.image(for: text) {
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

    /// 也用于「保存二维码到相册」，所以做成静态工厂。
    static func image(for text: String, scale: CGFloat = 12) -> UIImage? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
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
    @State private var alertMessage: String?
    @State private var savedQR = false

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
                                Text("点「重新取支付串」会依次试支付宝 / 微信 / 钱包，订单号 \(current.orderId)")
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Flat.textTertiary)
                                if let reason = store.lastPrepayError, !reason.isEmpty {
                                    Text(reason)
                                        .font(.system(size: 11))
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(Flat.orange)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Flat.surfaceLow)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button {
                                    Task {
                                        switching = true
                                        await store.reopenPrepay()
                                        switching = false
                                        if let param = store.pending?.prepayParam, !param.isEmpty {
                                            payTypeOverride = store.pending?.payType
                                        } else if let reason = store.lastPrepayError {
                                            alertMessage = reason
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        if switching { ProgressView().tint(Flat.textPrimary) }
                                        Text(switching ? "取支付串…" : "重新取支付串")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 46))
                                .disabled(switching)
                            }
                            .padding(16)
                            .flatCard()
                        }

                        Button {
                            saveQRToAlbum()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: savedQR ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(savedQR ? "已存入相册" : "保存二维码到相册")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FlatButtonStyle(tint: isWeChat ? Flat.green : Flat.accent,
                                                      filled: true, height: 50))

                        Button {
                            openScanner()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("打开\(payLabel)扫一扫")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FlatButtonStyle(tint: isWeChat ? Flat.green : Flat.accent,
                                                      filled: false, height: 46))

                        Button {
                            openInSafari()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(isWeChat ? "用 Safari 打开并唤起微信支付" : "用 Safari 打开支付页")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FlatButtonStyle(tint: Flat.cyan, filled: false, height: 46))

                        Text(isWeChat
                             ? "微信的 H5 支付必须在浏览器里发起才肯跳转：先点「用 Safari 打开」，页面里点去支付，系统才会把链接交给微信。"
                             : "支付宝对第三方直接调起收银台的限制越来越严，可以试「用 Safari 打开」，或保存二维码后用扫一扫的相册选图。")
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Flat.textTertiary)
                            .padding(.horizontal, 6)

                        Button {
                            openPayApp()
                        } label: {
                            Text("尝试直接调起\(payLabel)收银台")
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(FlatButtonStyle(tint: Flat.surfaceHigh, filled: false, height: 40))
                        .disabled(switching)

                        Button {
                            copyPayString()
                        } label: {
                            Text("复制支付链接")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(FlatButtonStyle(tint: Flat.surfaceHigh, filled: false, height: 44))

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
                            row("支付串", current.prepayParam.isEmpty
                                ? "空（点「重新取支付串」）"
                                : "\(current.prepayParam.count) 字符 · \(qrText.prefix(28))…")
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
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
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
                let error = await store.switchPayType(type)
                switching = false
                if store.pending?.payType == type {
                    payTypeOverride = type
                }
                if let error { alertMessage = error }
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

    /// 打开支付宝 / 微信的扫一扫，用户再从相册里选刚保存的二维码。
    private func openScanner() {
        guard let url = PGProtocol.qrScanScheme(payType: payType) else {
            alertMessage = "拼不出\(payLabel)扫一扫的链接"
            return
        }
        let app = UIApplication.shared
        app.open(url, options: [:]) { ok in
            guard !ok else { return }
            DispatchQueue.main.async {
                self.alertMessage = self.savedQR
                    ? "系统没放行打开\(self.payLabel)。可以手动打开\(self.payLabel)，用「扫一扫」右上角的相册选刚保存的二维码。"
                    : "系统没放行打开\(self.payLabel)。先点上面的「保存二维码到相册」，再手动打开\(self.payLabel)用相册扫码。"
            }
        }
    }

    /// 用 Safari 打开支付页：微信 H5 支付只有从浏览器发起才会把链接交给微信 App。
    private func openInSafari() {
        guard let url = PGProtocol.safariPayURL(for: current.prepayParam, payType: payType) else {
            alertMessage = "这笔单没有可用的网页支付链接（支付串 \(current.prepayParam.count) 字符）。可以在支付方式里切换一次渠道重新取串，或点「重新取支付串」。"
            return
        }
        UIApplication.shared.open(url, options: [:]) { ok in
            guard !ok else { return }
            DispatchQueue.main.async {
                self.alertMessage = "Safari 没接住这个链接，可以先点「复制支付链接」自己粘到浏览器。"
            }
        }
    }

    private func copyPayString() {
        let text = qrText
        guard !text.isEmpty else {
            alertMessage = "还没有支付串可复制。先点「重新取支付串」，或切换支付方式重新取一次。"
            return
        }
        UIPasteboard.general.string = text
        alertMessage = "已复制 \(text.count) 个字符。粘到\(payLabel)聊天框或浏览器地址栏都能用。"
        store.log("已复制支付串（\(text.count) 字符，payType=\(payType)）")
    }

    private func saveQRToAlbum() {
        guard let image = QRCodeView.image(for: qrText) else {
            alertMessage = "二维码生成失败（支付串 \(current.prepayParam.count) 字符），没法保存"
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        savedQR = true
        alertMessage = "已存入相册。接着点「打开\(payLabel)扫一扫」，在扫一扫右上角选「相册」，挑这张二维码即可付款。"
        store.log("二维码已保存到相册（\(qrText.count) 字符）")
    }

    private func openNext(_ urls: [URL], index: Int, payLabel: String) {
        guard index < urls.count else {
            alertMessage = (savedQR
                ? "\(payLabel)没有接管这个链接。二维码已在相册里，手动打开\(payLabel)用扫一扫的相册选图就能付。"
                : "\(payLabel)没有接管这个链接。先保存二维码到相册，再手动打开\(payLabel)用相册扫码。")
            return
        }
        let url = urls[index]
        // 不先用 canOpenURL 预判：它对 alipays:// / weixin:// 的判定经常与真实 open 结果不一致，
        // 直接 open 拿回调更准。
        UIApplication.shared.open(url, options: [:]) { ok in
            guard !ok else { return }
            DispatchQueue.main.async {
                self.openNext(urls, index: index + 1, payLabel: payLabel)
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
