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
            FlatSectionHeader(title: "支付方式")
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Flat.orange.opacity(0.16)).frame(width: 38, height: 38)
                    Image(systemName: "wallet.bifold.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Flat.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("余额支付")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text("当前余额 ¥ \(store.user?.balanceText ?? "—")")
                        .font(.system(size: 12))
                        .foregroundStyle(Flat.textTertiary)
                }
                Spacer()
                Button {
                    showingRecharge = true
                } label: {
                    Text("充值")
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
            Text("这台机器只支持余额扣款：下单后一次点击就扣余额、机器直接启动，不需要扫码。余额可在官方充值页充。")
                .font(.system(size: 11))
                .foregroundStyle(Flat.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .flatCard()
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
