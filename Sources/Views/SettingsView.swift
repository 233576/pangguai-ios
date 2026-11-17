import SwiftUI

/// 设置页：账号、支付方式、自动刷新、接口信息、关于。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showingLogin = false

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
            HStack(spacing: 10) {
                payOption(title: "支付宝", detail: "扫码付", value: PGProtocol.payTypeAlipay)
                payOption(title: "微信", detail: "扫一扫付", value: PGProtocol.payTypeWeChat)
            }
            HStack(spacing: 10) {
                payOption(title: "钱包余额", detail: "需先充值", value: PGProtocol.payTypeWallet)
                payOption(title: "支付宝免密", detail: "小额直扣", value: 15)
            }
            Text("下单后 App 会用选中的方式取支付串，出二维码；支付面板里还能随时切换支付宝 / 微信，订单号不变。")
                .font(.system(size: 11))
                .foregroundStyle(Flat.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .flatCard()
    }

    private func payOption(title: String, detail: String, value: Int) -> some View {
        Button {
            store.setPayType(value)
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .opacity(0.72)
            }
            .foregroundStyle(store.settings.payType == value ? Flat.accent : Flat.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .flatPill(selected: store.settings.payType == value,
                      tint: value == PGProtocol.payTypeWeChat ? Flat.green : Flat.accent)
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
