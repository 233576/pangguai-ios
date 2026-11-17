import SwiftUI
import UIKit
import WebKit

/// 充值页：余额只能在官方 H5 里充，这里把它装进应用内浏览器，令牌沿用当前登录。
/// 真正的充值入口是 H5 的 `buyGold`（通用小票充值），只需要店铺 ID（shopId）。
struct RechargeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private enum Page: String, CaseIterable, Identifiable {
        case recharge
        case wallet

        var id: String { rawValue }
        var title: String {
            switch self {
            case .recharge: return "充值"
            case .wallet: return "我的钱包"
            }
        }
    }

    @State private var page: Page = .recharge
    @State private var copied = false
    @State private var shopIdDraft = ""
    @State private var appliedShopId = ""
    @State private var editingShop = false

    private var shopId: String {
        if !appliedShopId.isEmpty { return appliedShopId }
        return store.device?.shopId ?? ""
    }

    private var url: URL? {
        switch page {
        case .recharge:
            return PGProtocol.rechargeURL(token: store.loginToken(), shopId: shopId)
        case .wallet:
            return PGProtocol.walletURL(token: store.loginToken())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                VStack(spacing: 0) {
                    banner

                    if store.loginToken().isEmpty {
                        emptyState
                    } else {
                        switcher
                        if page == .recharge {
                            shopField
                        }
                        if let url = url {
                            RechargeWebContainer(url: url)
                                .id(url.absoluteString)
                        } else {
                            missingShop
                        }
                    }
                }
            }
            .navigationTitle("账户充值")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Flat.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copied ? "已复制" : "复制链接") { copyLink() }
                        .foregroundStyle(Flat.accent)
                        .disabled(url == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if shopIdDraft.isEmpty { shopIdDraft = store.device?.shopId ?? "" }
        }
        .onDisappear { Task { await store.refreshProfile() } }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Flat.orange)
                Text("当前余额 ¥ \(store.user?.balanceText ?? "—")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Flat.textPrimary)
                Spacer()
                Button {
                    Task { await store.refreshProfile() }
                } label: {
                    Text("刷新")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Flat.accent)
                }
                .buttonStyle(.plain)
            }
            Text("充值是官方页面，付款完成后回来点一下「刷新」余额就会更新。")
                .font(.system(size: 11))
                .foregroundStyle(Flat.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Flat.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Flat.stroke).frame(height: 1)
        }
    }

    private var switcher: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .flatPill(selected: page == item, tint: Flat.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var shopField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("店铺 ID")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
                TextField("店铺 ID（当前机器所在网点）", text: $shopIdDraft)
                    .font(.system(size: 13, design: .monospaced))
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .flatField()
                if editingShop {
                    Button("打开") {
                        appliedShopId = shopIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        editingShop = false
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Flat.accent)
                } else {
                    Button("改") { editingShop = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Flat.textSecondary)
                }
            }
            HStack(spacing: 6) {
                Text(shopId.isEmpty ? "没有店铺 ID：先扫码识别一台洗衣机，或手填网点编号。" : "当前店铺：\(store.device?.orgName ?? "—") · \(shopId)")
                    .font(.system(size: 11))
                    .foregroundStyle(shopId.isEmpty ? Flat.orange : Flat.textTertiary)
                    .lineLimit(2)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var missingShop: some View {
        VStack(spacing: 12) {
            Image(systemName: "number.square")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Flat.textTertiary)
            Text("还没有店铺 ID")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Flat.textSecondary)
            Text("充值页按店铺开通。先在洗衣页扫码识别一台洗衣机，\n或者在上面手填网点编号后点「打开」。")
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Flat.textTertiary)
            Text("登录后才有充值链接")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Flat.textSecondary)
            Text("先在「洗衣」页登录手机号，再回来充值。")
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func copyLink() {
        guard let url = url else { return }
        UIPasteboard.general.string = url.absoluteString
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}

/// 极简 WKWebView 包装：只负责把充值页装进来，cookie 用默认持久存储。
/// 遇到 `alipays://` / `weixin://` 这类外部 scheme 就交给系统，让支付宝 / 微信能起来。
struct RechargeWebContainer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let current = webView.url else {
            webView.load(URLRequest(url: url))
            return
        }
        if current.absoluteString != url.absoluteString, webView.isLoading == false {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = target.scheme?.lowercased() ?? ""
            let external = ["alipays", "alipay", "alipayqr", "weixin", "weixinULAPI", "weixinURLParamsAPI",
                            "tel", "mailto", "itms-apps"]
            if external.contains(scheme) {
                decisionHandler(.cancel)
                UIApplication.shared.open(target, options: [:], completionHandler: nil)
                return
            }
            decisionHandler(.allow)
        }
    }
}
