import SwiftUI
import UIKit
import WebKit

/// 充值页：余额只能在官方 H5 里充，这里把它装进应用内浏览器，令牌沿用当前登录。
struct RechargeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false

    private var url: URL? {
        let orgId = store.device?.orgId ?? ""
        let shop = store.device?.orgName ?? ""
        return PGProtocol.rechargeURL(token: store.loginToken(), orgId: orgId, shopName: shop)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                if let url = url {
                    VStack(spacing: 0) {
                        banner
                        RechargeWebContainer(url: url)
                    }
                } else {
                    emptyState
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
            }
            Text("充值是官方页面，付款完成后回来点一下余额就会刷新。")
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
struct RechargeWebContainer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }
}
