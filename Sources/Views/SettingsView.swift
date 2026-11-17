import SwiftUI
import UIKit

/// 设置页：账号、支付方式、自动刷新、接口信息、关于。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showingLogin = false
    @State private var showingRecharge = false
    @State private var copiedToken: String?

    var body: some View {
        ZStack {
            FlatBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    accountCard
                    payCard
                    refreshCard
                    endpointCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 108)
            }
        }
        .sheet(isPresented: $showingLogin) {
            LoginSheet().environmentObject(store)
        }
        .sheet(isPresented: $showingRecharge) {
            RechargeView().environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("设置")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Flat.textPrimary)
            Text("只做洗衣机，别的一概不管")
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "账号")

            if store.loggedIn {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.phoneText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Flat.textPrimary)
                        Text("余额 \(store.user?.balanceText ?? "—")")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.textTertiary)
                    }
                    Spacer()
                    Text(store.user?.hasVip == true ? "会员" : "普通")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Flat.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .flatPill(selected: true)
                }

                Button {
                    store.logout()
                } label: {
                    Text("退出登录")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.red, filled: false, height: 44))
            } else {
                Text("还没有登录。登录一次，之后打开 App 会自动检测状态。")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
                Button {
                    showingLogin = true
                } label: {
                    Text("手机号登录")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 46))
            }
        }
        .padding(16)
        .flatCard()
    }

    private var payCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "默认支付方式")
            VStack(spacing: 8) {
                payOption(title: "微信支付", detail: "下单后出微信付款码 / 唤起微信",
                          tint: Flat.green, icon: "message.fill",
                          type: PGProtocol.payTypeWeChat)
                payOption(title: "支付宝", detail: "下单后出支付宝付款码",
                          tint: Flat.accent, icon: "a.circle.fill",
                          type: PGProtocol.payTypeAlipay)
                payOption(title: "余额支付", detail: "直接扣余额，余额 ¥\(store.user?.balanceText ?? "—")",
                          tint: Flat.orange, icon: "wallet.bifold.fill",
                          type: PGProtocol.payTypeWallet)
            }

            HStack(spacing: 10) {
                Button {
                    showingRecharge = true
                } label: {
                    Text("充值店铺余额")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.orange, filled: false, height: 40))
            }

            Text("支付面板里还能随时换渠道，订单号不变。余额不足时用微信/支付宝扫码即可。")
                .font(.system(size: 11))
                .foregroundStyle(Flat.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .flatCard()
    }

    private func payOption(title: String, detail: String, tint: Color,
                           icon: String, type: Int) -> some View {
        Button {
            store.setPayType(type)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.16)).frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)
                }
                Spacer()
                Image(systemName: store.settings.payType == type ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(store.settings.payType == type ? tint : Flat.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Flat.controlRadius, style: .continuous)
                    .fill(store.settings.payType == type ? tint.opacity(0.10) : Flat.surfaceHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Flat.controlRadius, style: .continuous)
                    .strokeBorder(store.settings.payType == type ? tint.opacity(0.45) : Flat.stroke,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var refreshCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlatSectionHeader(title: "启动自动检测")
            Toggle(isOn: Binding(
                get: { store.settings.autoRefresh },
                set: { store.setAutoRefresh($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("打开 App 等 2 秒自动查状态")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Flat.textPrimary)
                    Text("关掉就只在你手动点的时候刷新")
                        .font(.system(size: 11))
                        .foregroundStyle(Flat.textTertiary)
                }
            }
            .tint(Flat.accent)
        }
        .padding(16)
        .flatCard()
    }

    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlatSectionHeader(title: "接口信息")
            infoRow("服务地址", PGProtocol.base)
            infoRow("通道", PGProtocol.channel)
            infoRow("客户端版本", "\(PGProtocol.appVersion) (\(PGProtocol.versionCode))")
            infoRow("分类", PGProtocol.categoryCode)
        }
        .padding(16)
        .flatCard()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Flat.textSecondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlatSectionHeader(title: "关于")
            infoRow("版本", Self.appVersion)
            Text("协议参考 Cumpus / wash / baotuquan-light 三个开源项目，只复刻了洗衣机（categoryCode=wash）这一条链路：扫码 → 选套餐 → 下单 → 扫码支付 → 查订单。")
                .font(.system(size: 11))
                .foregroundStyle(Flat.textTertiary)
            Button {
                let token = store.loginToken()
                guard !token.isEmpty else {
                    copiedToken = "还没登录，没有凭证"
                    return
                }
                UIPasteboard.general.string = token
                copiedToken = "已复制 \(token.count) 个字符"
            } label: {
                Text("复制登录凭证（调试）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Flat.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .flatField()
            if let copiedToken {
                Text(copiedToken)
                    .font(.system(size: 11))
                    .foregroundStyle(Flat.textTertiary)
            }
        }
        .padding(16)
        .flatCard(fill: Flat.surfaceLow)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
