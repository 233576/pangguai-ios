import SwiftUI
import UIKit

/// 洗衣主页：账号 → 扫码/机器码 → 设备与套餐 → 最近用过 → 待支付。
struct LaundryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var code = ""
    @State private var showingLogin = false
    @State private var showingScan = false
    @State private var showingPay = false
    @State private var showingRecharge = false
    @State private var confirming: PGSku?

    var body: some View {
        ZStack {
            FlatBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    accountCard

                    if let running = store.runningOrder {
                        WashProgressCard(order: running, now: store.now)
                    } else if let paid = store.latestPaidOrder,
                              let end = paid.endsAt,
                              end.timeIntervalSince(store.now) > -300 {
                        WashProgressCard(order: paid, now: store.now)
                    }

                    scanCard

                    if let device = store.device {
                        deviceCard(device)
                    } else {
                        emptyDeviceCard
                    }

                    if let pending = store.pending {
                        pendingCard(pending)
                    }

                    if !store.recentDevices.isEmpty {
                        recentCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 108)
            }
            .refreshable {
                await store.refreshAll()
            }
        }
        .sheet(isPresented: $showingLogin) {
            LoginSheet {
                let target = code.trimmingCharacters(in: .whitespaces)
                guard !target.isEmpty else { return }
                Task { _ = await store.resolve(code: target) }
            }
            .environmentObject(store)
        }
        .onChange(of: store.needsLogin) { wanted in
            guard wanted else { return }
            store.needsLogin = false
            showingScan = false
            showingLogin = true
        }
        .sheet(isPresented: $showingScan) {
            ScanSheet { scanned in
                code = scanned
                Task { _ = await store.resolve(code: scanned) }
            }
        }
        .sheet(isPresented: $showingPay) {
            if let pending = store.pending {
                PaySheet(payment: pending).environmentObject(store)
            }
        }
        .sheet(isPresented: $showingRecharge) {
            RechargeView().environmentObject(store)
        }
        .confirmationDialog(
            confirming.map { "确认下单：\($0.name) \($0.priceText)" } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let sku = confirming {
                Button("用\(PGProtocol.payTitle(store.settings.payType))付 \(sku.priceText)") {
                    let target = sku
                    confirming = nil
                    Task {
                        let ok = await store.placeOrder(sku: target)
                        if ok { showingPay = true }
                    }
                }
                Button("取消", role: .cancel) { confirming = nil }
            }
        } message: {
            Text("付款后洗衣机才会启动；未付款的订单可以在订单页撤销。")
        }
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("已完成", isPresented: Binding(
            get: { store.noticeMessage != nil },
            set: { if !$0 { store.noticeMessage = nil } }
        )) {
            Button("好", role: .cancel) { store.noticeMessage = nil }
        } message: {
            Text(store.noticeMessage ?? "")
        }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("胖乖洗衣")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Flat.textPrimary)
                Text("洗衣机 · 扫码即用")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
            }
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Flat.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Flat.surfaceHigh)
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
        }
        .padding(.top, 12)
    }

    private var accountCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Flat.accent.opacity(0.18)).frame(width: 42, height: 42)
                Image(systemName: store.loggedIn ? "person.fill" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Flat.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.loggedIn ? store.phoneText : "未登录")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Flat.textPrimary)
                Text(store.loggedIn
                     ? "余额 \(store.user?.balanceText ?? "—") · 店铺 \(store.shopBalanceText)\(store.user?.hasVip == true ? " · 会员" : "")"
                     : "手机号 + 验证码，10 秒登录")
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
            }

            Spacer()

            if store.loggedIn {
                Button("充值") { showingRecharge = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Flat.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Flat.orange.opacity(0.15))
                    )
                    .buttonStyle(.plain)

                Button("退出") { store.logout() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Flat.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Flat.surfaceHigh)
                    )
                    .buttonStyle(.plain)
            } else {
                Button("登录") { showingLogin = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Flat.accent)
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .flatCard()
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("机器码")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Flat.textSecondary)
                if !store.loggedIn {
                    Text("先登录")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Flat.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Flat.orange.opacity(0.16))
                        )
                }
                Spacer()
            }

            HStack(spacing: 10) {
                TextField("扫码得到的码，或直接粘贴", text: $code)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .flatField()

                Button {
                    if store.loggedIn {
                        showingScan = true
                    } else {
                        store.errorMessage = nil
                        showingLogin = true
                    }
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.surfaceHigh, filled: false, height: 46))
            }

            if !store.loggedIn {
                Text("扫码接口必须带登录凭证，未登录时服务端会回一句「版本过低」，其实是没登录。")
                    .font(.system(size: 11))
                    .foregroundStyle(Flat.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if store.loggedIn {
                    let target = code
                    Task { _ = await store.resolve(code: target) }
                } else {
                    store.errorMessage = nil
                    showingLogin = true
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isBusy { ProgressView().tint(.white) }
                    Text(store.isBusy ? store.busyText : (store.loggedIn ? "查询这台洗衣机" : "登录后查询"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 50))
            .disabled(store.isBusy || code.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .flatCard()
    }

    private func deviceCard(_ device: PGDeviceDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Flat.cyan.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "washer.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Flat.cyan)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text(device.subtitle.isEmpty ? "洗衣机" : device.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Flat.textTertiary)
                }
                Spacer()
                if !device.serviceTelephone.isEmpty {
                    Button {
                        if let url = URL(string: "tel://\(device.serviceTelephone)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Flat.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Flat.surfaceHigh)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            FlatDivider(inset: 0)

            if store.skus.isEmpty {
                Text("这台机器暂时没有可选套餐")
                    .font(.system(size: 13))
                    .foregroundStyle(Flat.textTertiary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.skus) { sku in
                        Button {
                            confirming = sku
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sku.name.isEmpty ? "标准洗" : sku.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Flat.textPrimary)
                                    if !sku.feature.isEmpty {
                                        Text(sku.feature)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Flat.textTertiary)
                                    }
                                }
                                Spacer()
                                Text(sku.priceText)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Flat.accent)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Flat.textTertiary)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if sku.id != store.skus.last?.id {
                            FlatDivider(inset: 0)
                        }
                    }
                }
            }
        }
        .padding(16)
        .flatCard()
    }

    private var emptyDeviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有选洗衣机")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Flat.textPrimary)
            Text("扫一下洗衣机身上的二维码，或者直接输入机器码；也可以在下面「最近用过」里点一台。")
                .font(.system(size: 12))
                .foregroundStyle(Flat.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flatCard(fill: Flat.surfaceLow)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlatSectionHeader(
                title: "最近用过",
                trailing: AnyView(
                    Text("\(store.recentDevices.count) 台")
                        .font(.system(size: 12))
                        .foregroundStyle(Flat.textTertiary)
                )
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.recentDevices) { item in
                        Button {
                            Task { await store.selectDevice(goodsId: item.goodsId) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name.isEmpty ? "洗衣机" : item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Flat.textPrimary)
                                    .lineLimit(1)
                                Text(item.orgName.isEmpty ? item.statusText : item.orgName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Flat.textTertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(width: 168, alignment: .leading)
                            .flatCard(fill: store.device?.goodsId == item.goodsId
                                      ? Flat.accent.opacity(0.14)
                                      : Flat.surfaceHigh)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .flatCard()
    }

    private func pendingCard(_ pending: PendingPayment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Flat.orange.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Flat.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("有 1 笔待支付")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Flat.textPrimary)
                Text(pending.machineName.isEmpty ? pending.orderId : pending.machineName)
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.textTertiary)
                Text("\(PGProtocol.payTitle(pending.payType)) · ¥\(pending.price.isEmpty ? "0.00" : pending.price)")
                    .font(.system(size: 11))
                    .foregroundStyle(Flat.textTertiary)
            }
            Spacer()
            Button("去支付") { showingPay = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Flat.orange)
                )
                .buttonStyle(.plain)
        }
        .padding(14)
        .flatCard()
    }
}
