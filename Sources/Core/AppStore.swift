import Foundation
import UIKit

@MainActor
final class AppStore: ObservableObject {
    // MARK: - 状态

    @Published private(set) var settings = Settings()
    @Published private(set) var user: PGUser?
    @Published private(set) var balances: [PGBalanceItem] = []
    @Published private(set) var recentDevices: [PGRecentDevice] = []
    @Published private(set) var device: PGDeviceDetail?
    @Published private(set) var skus: [PGSku] = []
    @Published private(set) var orders: [PGOrder] = []
    @Published private(set) var pending: PendingPayment?
    @Published private(set) var logs: [String] = []

    @Published private(set) var loggedIn = false
    @Published private(set) var busyText = ""
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    /// 未登录却被要求扫码时置位，由界面弹出登录浮层。
    @Published var needsLogin = false
    /// 最近一次取支付串失败的原因（含每个渠道的 code/msg），支付面板直接展示。
    @Published private(set) var lastPrepayError: String?
    /// 最近一次 prePay 的原始响应（干跑诊断用，成功时清空）。
    @Published private(set) var lastPrepayRaw: String = ""
    /// 当前这台机器真实开通的支付渠道（`/pay/ticket/getAvailablePayTypeList`）。
    @Published private(set) var payOptions: [PayOption] = []

    @Published private(set) var codeCountdown = 0
    @Published private(set) var lastQueryCode = ""

    /// 每秒跳动一次，驱动洗涤倒计时。只有界面里真的显示倒计时时才跑，省电。
    @Published private(set) var now = Date()
    /// 进行中订单的设备异常提示（服务端有就给，没有就是 nil）。
    @Published private(set) var deviceAlert: DeviceAlert?

    /// 设备详情里服务端直接下发的故障文案（`deviceErrorMsg`）优先于订单详情的启发式推断。
    var activeAlert: DeviceAlert? {
        if let detail = device, detail.hasDeviceError {
            return DeviceAlert(title: "设备异常，已暂停", detail: detail.deviceErrorText)
        }
        return deviceAlert
    }
    /// 最近一次 `/order/detail` 的原始响应，供「复制诊断信息」用。
    @Published private(set) var lastDetailRaw: String = ""

    private var lastDetailAt = Date.distantPast
    private var detailBusy = false
    private var clock: Timer?
    private var finishedOrderIds: Set<String> = []

    private var client = PGClient()
    private var countdownTask: Task<Void, Never>?

    private let settingsKey = "pangguai.settings.v1"
    private let pendingKey = "pangguai.pending.v1"
    private let tokenAccount = "pangguai.token"
    private let phoneAccount = "pangguai.phone"

    nonisolated init() {}

    var isBusy: Bool { !busyText.isEmpty }

    var phoneText: String {
        if let phone = user?.phone, !phone.isEmpty { return phone }
        return settings.lastPhone
    }

    var hasToken: Bool { loggedIn }

    /// 调试用：把当前登录凭证交给界面复制。只在用户自己点「复制」时读取，
    /// 不写日志、不上报，方便在电脑上复现接口问题。
    func loginToken() -> String { client.token }

    // MARK: - 本地存储

    func restore() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        }
        if let data = UserDefaults.standard.data(forKey: pendingKey),
           let decoded = try? JSONDecoder().decode(PendingPayment.self, from: data) {
            pending = decoded
        }
        if let stored = Keychain.load(account: tokenAccount) {
            let token = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                client = PGClient(token: token)
                loggedIn = true
                if let phone = Keychain.load(account: phoneAccount), !phone.isEmpty {
                    user = PGUser(phone: phone, balance: "", hasVip: false)
                }
                log("已载入登录状态")
            }
        }
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func persistPending() {
        if let payment = pending, let data = try? JSONEncoder().encode(payment) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
    }

    private func storeToken(_ token: String, phone: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(clean, account: tokenAccount)
        Keychain.save(phone, account: phoneAccount)
        client = PGClient(token: clean)
        loggedIn = !clean.isEmpty
        log("登录成功，凭证长度 \(clean.count)")
    }

    // MARK: - 设置

    func setAutoRefresh(_ value: Bool) {
        settings.autoRefresh = value
        persistSettings()
    }

    func setPayType(_ value: Int) {
        settings.payType = value
        persistSettings()
    }

    // MARK: - 日志

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        logs.append(line)
        if logs.count > 400 {
            logs.removeFirst(logs.count - 400)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - 登录

    /// 直接粘贴凭证登录。胖乖小程序和 App 共用同一套 token，
    /// 所以从电脑端抓到 `token=xxxx` 后粘进来就能用，不需要短信验证码。
    func login(withToken raw: String) async {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 允许直接粘贴 `token=xxx` 或者整段表单
        if let range = clean.range(of: "token=") {
            clean = String(clean[range.upperBound...])
            if let amp = clean.firstIndex(of: "&") { clean = String(clean[..<amp]) }
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 16 else {
            errorMessage = "这一串看起来不是 token（太短了）"
            return
        }
        storeToken(clean, phone: settings.lastPhone)
        busyText = "验证凭证…"
        await refreshProfile()
        busyText = ""
        if user != nil {
            noticeMessage = "登录成功：\(user?.phone ?? "")"
            await refreshDevices()
        } else {
            errorMessage = "凭证无效或已过期，请在官方小程序里重新登录后再抓一次"
        }
    }

    func sendCode(phone: String) async -> Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 11 else {
            errorMessage = "请输入 11 位手机号"
            return false
        }
        busyText = "发送验证码…"
        let response = await client.sendCode(phone: trimmed)
        busyText = ""
        log("发送验证码 → code=\(response.code) \(response.message)")
        if response.ok {
            settings.lastPhone = trimmed
            persistSettings()
            startCountdown()
            noticeMessage = "验证码已发送"
            return true
        }
        errorMessage = response.message
        return false
    }

    private func startCountdown() {
        countdownTask?.cancel()
        codeCountdown = 60
        countdownTask = Task { [weak self] in
            while let self, self.codeCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.codeCountdown -= 1
            }
        }
    }

    func login(phone: String, code: String) async -> Bool {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard trimmedPhone.count >= 11, !trimmedCode.isEmpty else {
            errorMessage = "手机号或验证码不完整"
            return false
        }
        busyText = "登录中…"
        let response = await client.login(phone: trimmedPhone, verify: trimmedCode)
        busyText = ""
        log("登录 /user/reg → code=\(response.code) \(response.message)")

        guard response.ok, let data = response.dataObject else {
            errorMessage = response.message
            return false
        }
        let token = data.text("token")
        guard !token.isEmpty else {
            errorMessage = "服务端没有返回 token"
            return false
        }
        storeToken(token, phone: trimmedPhone)
        settings.lastPhone = trimmedPhone
        persistSettings()
        user = PGUser(phone: trimmedPhone,
                      balance: data.text("balance"),
                      hasVip: data.boolValue("hasVip"))
        noticeMessage = "登录成功"
        await refreshAll()
        return true
    }

    func logout() {
        Keychain.delete(account: tokenAccount)
        Keychain.delete(account: phoneAccount)
        client = PGClient()
        loggedIn = false
        user = nil
        device = nil
        skus = []
        recentDevices = []
        orders = []
        pending = nil
        persistPending()
        log("已退出登录")
    }

    // MARK: - 身份与设备列表

    func refreshProfile() async {
        guard loggedIn else { return }
        let response = await client.userInfo()
        if response.isUnauthorized {
            log("身份失效，需要重新登录")
            logout()
            errorMessage = "登录已过期，请重新登录"
            return
        }
        guard response.ok, let data = response.dataObject else {
            log("获取用户信息失败：\(response.message)")
            return
        }
        user = PGUser(phone: data.text("phone"),
                      balance: data.text("balance"),
                      hasVip: data.boolValue("hasVip"))
        if let phone = user?.phone, !phone.isEmpty {
            settings.lastPhone = phone
            persistSettings()
        }
        log("用户信息：\(user?.phone ?? "-") 余额 \(user?.balanceText ?? "-")")
        await refreshBalances()
    }

    /// 店铺（受限）余额：`/user/astrict/list`。充值页与支付页都要显示，钱到底进了哪儿一目了然。
    func refreshBalances() async {
        guard loggedIn else { return }
        let response = await client.astrictList()
        if response.isUnauthorized {
            logout()
            errorMessage = "登录已过期，请重新登录"
            return
        }
        guard response.ok else {
            log("店铺余额失败：\(response.message)")
            return
        }
        let list = response.dataArray ?? []
        balances = list.map { row in
            PGBalanceItem(remainCoin: row.text("remainCoin"),
                          shopNames: row.text("shopNames"),
                          machineTypeNames: row.text("machineTypeNames"))
        }
        let total = balances.reduce(0) { $0 + $1.amount }
        if !balances.isEmpty {
            log("店铺余额：\(balances.count) 项，合计 ¥\(String(format: "%.2f", total))")
        }
    }

    /// 当前网点可用余额（店铺余额合计）。
    var shopBalanceTotal: Double {
        balances.reduce(0) { $0 + $1.amount }
    }

    var shopBalanceText: String {
        balances.isEmpty ? "—" : "¥\(String(format: "%.2f", shopBalanceTotal))"
    }

    func refreshDevices() async {
        guard loggedIn else { return }
        let response = await client.latestDevices()
        if response.isUnauthorized {
            logout()
            errorMessage = "登录已过期，请重新登录"
            return
        }
        guard response.ok else {
            log("最近洗衣机失败：\(response.message)")
            return
        }
        let list = response.dataArray ?? []
        recentDevices = list.map { row in
            PGRecentDevice(
                goodsId: row.text("goodsId"),
                name: row.text("goodsName").isEmpty ? row.text("name") : row.text("goodsName"),
                orgName: row.text("orgName"),
                workStatus: row.intValue("workStatus", -1)
            )
        }.filter { !$0.goodsId.isEmpty }
        log("最近洗衣机 \(recentDevices.count) 台")
    }

    func refreshAll() async {
        await refreshProfile()
        await refreshDevices()
        await refreshOrders()
    }

    /// 启动后等 2 秒再自动刷新，避免刚开 App 就并发打接口。
    func autoDetectOnLaunch() async {
        guard loggedIn, settings.autoRefresh else { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        busyText = "自动检测…"
        await refreshAll()
        busyText = ""
    }

    // MARK: - 选设备

    func resolve(code: String) async -> Bool {
        // 服务端在 token 为空时对 /goods/scan/v2 回“版本过低，请升级APP”，
        // 这是它的兜底文案，真实含义是“没有登录”。所以本地先拦住。
        guard loggedIn else {
            busyText = ""
            lastQueryCode = ""
            errorMessage = "请先登录手机号账号，再扫码识别洗衣机"
            needsLogin = true
            log("扫码被拦下 → 当前未登录（服务端会误报「版本过低」）")
            return false
        }
        let cleaned = normalizedCode(code)
        guard !cleaned.isEmpty else {
            errorMessage = "请扫码或输入机器码"
            return false
        }
        lastQueryCode = cleaned
        busyText = "查询洗衣机…"
        let scanResponse = await client.scan(code: cleaned)
        if scanResponse.isUnauthorized {
            busyText = ""
            logout()
            errorMessage = "登录已过期，请重新登录"
            needsLogin = true
            return false
        }
        guard scanResponse.ok, let data = scanResponse.dataObject else {
            busyText = ""
            log("扫码失败 → code=\(scanResponse.code) \(scanResponse.message)")
            errorMessage = scanResponse.friendlyMessage
            return false
        }
        let goodsId = data.text("id").isEmpty ? data.text("goodsId") : data.text("id")
        guard !goodsId.isEmpty else {
            busyText = ""
            errorMessage = "机器码没有对应到设备"
            return false
        }
        let categoryName = data.text("categoryName")
        if !categoryName.isEmpty, !categoryName.contains("洗衣") {
            busyText = ""
            errorMessage = "这台设备是「\(categoryName)」，本 App 只支持洗衣机"
            log("扫码 \(cleaned) → 分类是 \(categoryName)，已拒绝")
            return false
        }
        log("扫码 \(cleaned) → goodsId \(goodsId) · shopId \(data.text("shopId")) · \(categoryName)")
        let ok = await loadDevice(goodsId: goodsId)
        busyText = ""
        return ok
    }

    func selectDevice(goodsId: String) async {
        busyText = "载入设备…"
        _ = await loadDevice(goodsId: goodsId)
        busyText = ""
    }

    @discardableResult
    private func loadDevice(goodsId: String) async -> Bool {
        let detailResponse = await client.deviceDetail(goodsId: goodsId)
        guard detailResponse.ok, let data = detailResponse.dataObject else {
            log("设备详情失败 → code=\(detailResponse.code) \(detailResponse.message)")
            errorMessage = detailResponse.message
            return false
        }
        let detail = PGDeviceDetail(
            goodsId: data.text("goodsId").isEmpty ? goodsId : data.text("goodsId"),
            name: data.text("name"),
            orgName: data.text("orgName"),
            orgId: data.text("orgId"),
            shopId: data.text("shopId"),
            categoryCode: data.text("categoryCode"),
            brandName: data.text("brandName"),
            soldState: data.intValue("soldState"),
            serviceTelephone: data.text("serviceTelephone"),
            deviceId: data.text("imei"),
            deviceErrorCode: data.text("deviceErrorCode"),
            deviceErrorMsg: data.text("deviceErrorMsg"),
            announcementContent: data.text("announcementContent"),
            imei: data.text("imei"),
            machineId: data.text("machineId"),
            payment: data.text("payment"),
            tradeMain: data.intValue("tradeMain"),
            isBluetooth: data.intValue("isBluetooth"),
            remainTime: data.intValue("remainTime"),
            payTypes: (data["payTypes"] as? [Any])?.compactMap { value -> Int? in
                if let v = value as? Int { return v }
                if let v = value as? String { return Int(v) }
                if let v = value as? NSNumber { return v.intValue }
                return nil
            } ?? []
        )
        device = detail
        log("设备：\(detail.name)（\(detail.subtitle)）payTypes=\(detail.payTypes) remainTime=\(detail.remainTime)")
        if detail.hasDeviceError {
            log("设备异常：\(detail.deviceErrorText)")
        }
        if !detail.announcementContent.isEmpty {
            log("公告：\(detail.announcementContent)")
        }

        let skuResponse = await client.skus(goodsId: goodsId)
        if skuResponse.ok, let rows = skuResponse.dataArray {
            skus = rows.map { row in
                PGSku(skuId: row.text("skuId"),
                      name: row.text("name"),
                      feature: row.text("feature"),
                      price: row.text("price"),
                      unit: row.text("unit"),
                      stockState: row.intValue("stockState", 1))
            }.filter { !$0.skuId.isEmpty }
            log("可选套餐 \(skus.count) 个")
        } else {
            skus = []
            log("套餐列表失败：\(skuResponse.message)")
        }
        return true
    }

    // MARK: - 下单与支付

    func placeOrder(sku: PGSku, payType: Int? = nil) async -> Bool {
        guard let detail = device else {
            errorMessage = "先选一台洗衣机"
            return false
        }
        let channel = payType ?? settings.payType
        busyText = "下单中…"
        let trade = await client.createTrade(orgId: detail.orgId,
                                             goodsId: detail.goodsId,
                                             skuId: sku.skuId)
        if trade.isUnauthorized {
            busyText = ""
            logout()
            errorMessage = "登录已过期，请重新登录"
            return false
        }
        if let blocked = trade.unpaidBlockOrderId {
            busyText = ""
            log("有未支付订单 \(blocked)，先处理它")
            errorMessage = "有未完成的订单（\(blocked)），请先在订单页处理"
            await refreshOrders()
            return false
        }
        guard trade.ok, let data = trade.dataObject else {
            busyText = ""
            log("下单失败 → code=\(trade.code) \(trade.message)")
            errorMessage = trade.message
            return false
        }
        let orderId = data.text("orderId").isEmpty ? data.text("tradeNo") : data.text("orderId")
        guard !orderId.isEmpty else {
            busyText = ""
            errorMessage = "下单没有返回订单号"
            return false
        }
        log("下单成功 orderId=\(orderId)，用\(PGProtocol.payTitle(channel))")

        await loadPayOptions(detail)
        let outcome = await requestPrePay(orderNo: orderId, payType: channel)
        busyText = ""
        if outcome.walletPaid {
            lastPrepayError = nil
            pending = nil
            persistPending()
            noticeMessage = "已用余额付掉 \(orderId)"
            await refreshOrders()
            await refreshProfile()
            return true
        }
        if outcome.param.isEmpty {
            lastPrepayError = outcome.detail
            errorMessage = "订单已创建（\(orderId)），\(outcome.detail)"
            await refreshOrders()
            return false
        }
        lastPrepayError = nil
        pending = PendingPayment(orderId: orderId,
                                 goodsId: detail.goodsId,
                                 skuId: sku.skuId,
                                 skuName: sku.name,
                                 price: sku.price,
                                 machineName: detail.name,
                                 orgName: detail.orgName,
                                 payType: outcome.payType,
                                 prepayParam: outcome.param,
                                 createdAt: Date())
        persistPending()
        await refreshOrders()
        log("支付串已就绪（\(PGProtocol.payTitle(outcome.payType))，\(outcome.param.count) 字符）")
        return true
    }

    func reopenPrepay() async {
        guard let current = pending else { return }
        busyText = "重新获取支付串…"
        if payOptions.isEmpty, let detail = device {
            await loadPayOptions(detail)
        }
        let outcome = await requestPrePay(orderNo: current.orderId, payType: current.payType)
        busyText = ""
        if outcome.walletPaid {
            lastPrepayError = nil
            pending = nil
            persistPending()
            noticeMessage = "已用余额付掉 \(current.orderId)"
            await refreshOrders()
            await refreshProfile()
            return
        }
        if outcome.param.isEmpty {
            lastPrepayError = outcome.detail
            errorMessage = outcome.detail
            return
        }
        lastPrepayError = nil
        var updated = current
        updated.payType = outcome.payType
        updated.prepayParam = outcome.param
        pending = updated
        persistPending()
    }

    /// 支付面板上换渠道：同一笔订单号重新取一次支付串。
    @discardableResult
    func switchPayType(_ type: Int) async -> String? {
        guard let current = pending else { return "没有待支付订单" }
        guard current.payType != type else { return nil }
        let outcome = await requestPrePay(orderNo: current.orderId, payType: type)
        if outcome.walletPaid {
            lastPrepayError = nil
            pending = nil
            persistPending()
            noticeMessage = "已用余额付掉 \(current.orderId)"
            await refreshOrders()
            await refreshProfile()
            return nil
        }
        if outcome.param.isEmpty {
            lastPrepayError = outcome.detail
            return outcome.detail
        }
        var updated = current
        updated.payType = outcome.payType
        updated.prepayParam = outcome.param
        pending = updated
        persistPending()
        lastPrepayError = nil
        log("切换到\(PGProtocol.payTitle(type))，支付串 \(outcome.param.count) 字符")
        return nil
    }

    struct PrePayOutcome {
        var payType: Int = PGProtocol.payTypeWallet
        var param: String = ""
        var detail: String
        /// 余额已经直接扣掉了（不需要二维码）。
        var walletPaid: Bool = false
    }

    /// 问服务端这台机器开了哪些渠道，用来决定支付面板上给哪些选项。
    func loadPayOptions(_ detail: PGDeviceDetail) async {
        let response = await client.availablePayTypes(goodsId: detail.goodsId,
                                                      shopId: detail.shopId,
                                                      orgId: detail.orgId,
                                                      imei: detail.deviceId,
                                                      categoryCode: detail.categoryCode)
        let options = response.payOptions
        payOptions = options
        if response.ok, !options.isEmpty {
            let text = options.map { "\($0.type)=\($0.title)" }.joined(separator: "、")
            log("这台机器可用支付方式：\(text)")
        } else {
            log("可用支付方式查询失败：code=\(response.code) \(response.message)")
        }
    }

    /// 取支付串。`payType == 2` 走 `/pay/unify/pay` 直接扣余额；
    /// 其它渠道走 `/pay/unify/prePay`，把 `prepayParam` 原样带回来给支付面板处理。
    func requestPrePay(orderNo: String, payType: Int = PGProtocol.payTypeWeChat) async -> PrePayOutcome {
        lastPrepayRaw = ""
        if payType == PGProtocol.payTypeWallet {
            let wallet = await client.walletPay(orderNo: orderNo)
            lastPrepayRaw = "walletPay\n\(wallet.body)"
            if wallet.ok {
                log("余额支付成功 \(orderNo)")
                return PrePayOutcome(payType: PGProtocol.payTypeWallet, detail: "", walletPaid: true)
            }
            if wallet.isUnauthorized {
                return PrePayOutcome(payType: PGProtocol.payTypeWallet, detail: "登录已失效，请重新登录后再试")
            }
            log("余额支付失败 → code=\(wallet.code) \(wallet.message)")
            log("原始响应：\(String(wallet.body.prefix(1200)))")
            return PrePayOutcome(payType: PGProtocol.payTypeWallet,
                                 detail: "余额支付失败：\(wallet.friendlyMessage)")
        }

        // 微信渠道服务端只认 31；旧值 32 做一次兜底重试
        var response = await client.prePay(orderNo: orderNo, payType: payType)
        if payType == PGProtocol.payTypeWeChat, PGProtocol.deepPayParam(in: response.dataObject).isEmpty {
            let retry = await client.prePay(orderNo: orderNo, payType: PGProtocol.payTypeWeChatLegacy)
            if !PGProtocol.deepPayParam(in: retry.dataObject).isEmpty { response = retry }
        }
        lastPrepayRaw = "prePay(payType=\(payType))\n\(response.body)"
        if response.isUnauthorized {
            return PrePayOutcome(payType: payType, detail: "登录已失效，请重新登录后再试")
        }
        let param = PGProtocol.deepPayParam(in: response.dataObject)
        if response.ok, !param.isEmpty {
            log("\(PGProtocol.payTitle(payType))支付串 \(param.count) 字符")
            return PrePayOutcome(payType: payType, param: param, detail: "")
        }
        log("取支付串失败 → code=\(response.code) \(response.message)")
        log("原始响应：\(String(response.body.prefix(1200)))")
        let available = response.payTypeList
        if !available.isEmpty {
            let names = available.map { "\(PGProtocol.payTitle($0))" }.joined(separator: "、")
            return PrePayOutcome(payType: payType,
                                 detail: "这台机器只开通了：\(names)。换成那个方式再试。")
        }
        return PrePayOutcome(payType: payType, detail: response.friendlyMessage)
    }

    /// 支付面板上的「立即支付」：扣余额。
    /// 返回非 nil 表示失败原因，交给面板直接弹出来。
    @discardableResult
    func payWithWallet() async -> String? {
        guard let current = pending else { return "没有待支付订单" }
        busyText = "余额支付中…"
        let wallet = await client.walletPay(orderNo: current.orderId)
        busyText = ""
        if wallet.ok {
            pending = nil
            persistPending()
            log("余额支付成功 \(current.orderId)")
            noticeMessage = "已用余额付掉 \(current.orderId)"
            await refreshOrders()
            await refreshProfile()
            return nil
        }
        log("余额支付失败 → code=\(wallet.code) \(wallet.message)")
        log("原始响应：\(String(wallet.body.prefix(1200)))")
        lastPrepayRaw = "walletPay\n\(wallet.body)"
        return wallet.friendlyMessage
    }


    /// 查这笔单付了没；已付就把本地挂单清掉。
    func checkPendingPayment() async -> Bool {
        guard let current = pending else { return false }
        busyText = "查询支付结果…"
        let response = await client.payStatus(orderNo: current.orderId, payType: current.payType)
        busyText = ""
        let paid = response.ok && (response.json["data"] as? Bool ?? false)
        log("支付状态 \(current.orderId) → \(paid ? "已支付" : "未支付")")
        if paid {
            pending = nil
            persistPending()
            noticeMessage = "支付成功，洗衣机即将启动"
            await refreshOrders()
        } else if !response.ok {
            errorMessage = "查询失败：\(response.message)"
        }
        return paid
    }

    func cancelPending() async {
        guard let current = pending else { return }
        busyText = "撤销订单…"
        let response = await client.cancelOrder(orderId: current.orderId)
        busyText = ""
        if response.ok {
            pending = nil
            persistPending()
            log("已撤销订单 \(current.orderId)")
            noticeMessage = "订单已撤销"
            await refreshOrders()
        } else {
            errorMessage = "撤销失败：\(response.message)"
        }
    }

    // MARK: - 订单列表

    func refreshOrders() async {
        guard loggedIn else { return }
        let response = await client.orders()
        guard response.ok else {
            if response.isUnauthorized { logout() }
            log("订单列表失败：\(response.message)")
            return
        }
        var rows: [[String: Any]] = []
        if let data = response.dataObject, let items = data["items"] as? [[String: Any]] {
            rows = items
        } else if let direct = response.dataArray {
            rows = direct
        }
        orders = rows.map { row in
            PGOrder(id: row.text("id"),
                    orderNo: row.text("orderNo"),
                    status: row.intValue("orderStatus"),
                    createTime: row.text("createTime"),
                    payPrice: row.text("payPrice"),
                    markPrice: row.text("markPrice"),
                    machineName: row.text("machineName"),
                    shopName: row.text("shopName"),
                    functionName: row.text("machineFunctionName"),
                    minutes: row.intValue("markMinutes"))
        }
        log("订单 \(orders.count) 条")
    }

    func cancel(order: PGOrder) async {
        busyText = "撤销中…"
        let response = await client.cancelOrder(orderId: order.id.isEmpty ? order.orderNo : order.id)
        busyText = ""
        if response.ok {
            noticeMessage = "订单已撤销"
            await refreshOrders()
        } else {
            errorMessage = "撤销失败：\(response.message)"
        }
    }

    // MARK: - 洗涤进度

    /// 当前正在洗的订单（服务端 status 1/2 且未到预计结束时间）。
    var runningOrder: PGOrder? {
        orders.first { $0.isRunning(now: now) }
    }

    /// 最近一笔已支付的订单，倒计时结束后用来显示「洗好了」。
    var latestPaidOrder: PGOrder? {
        orders.first { $0.isPaid }
    }

    func startClock() {
        guard clock == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.checkFinish()
                if self.now.timeIntervalSince(self.lastDetailAt) > 25 {
                    Task { await self.refreshActiveDetail() }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    /// 倒计时走完的那一下：震动 + 记一条日志，只触发一次。
    private func checkFinish() {
        for order in orders where order.isPaid {
            guard let end = order.endsAt, end <= now else { continue }
            // 只对最近一天的单子响一次，避免打开 App 时被历史订单震到。
            guard now.timeIntervalSince(end) < 24 * 3600 else { continue }
            let key = order.id.isEmpty ? order.orderNo : order.id
            guard !finishedOrderIds.contains(key) else { continue }
            finishedOrderIds.insert(key)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            log("洗涤完成：\(order.title)  \(order.functionName)")
        }
    }

    // MARK: - 设备异常

    /// 拉一次进行中订单的详情，解析出「设备异常 / 已暂停」这类提示。
    /// 官方没有专门的异常推送接口，只能靠订单详情里的状态字段。
    func refreshActiveDetail() async {
        guard loggedIn, let order = runningOrder ?? latestPaidOrder else {
            deviceAlert = nil
            return
        }
        guard !detailBusy else { return }
        detailBusy = true
        lastDetailAt = Date()
        let orderId = order.id.isEmpty ? order.orderNo : order.id
        let response = await client.orderDetail(orderId: orderId)
        detailBusy = false

        guard let data = response.dataObject else {
            lastDetailRaw = response.body
            return
        }
        lastDetailRaw = response.body
        deviceAlert = Self.deviceAlert(from: data)
    }

    /// 服务端字段名不统一，按关键字找「像异常说明」的字符串。
    static func deviceAlert(from data: [String: Any]) -> DeviceAlert? {
        let noisy = ["成功", "正常", "操作成功", "0", "null", "无", "暂未", "暂无"]
        func clean(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 1) 先看常见字段名，命中直接用
        let preferred = ["errorMsg", "errMsg", "faultMsg", "deviceMsg", "pauseReason",
                         "stopReason", "abnormalMsg", "statusDesc", "workStatusDesc",
                         "deviceStatusDesc", "remark", "message"]
        for key in preferred {
            if let value = data[key] as? String {
                let text = clean(value)
                if !text.isEmpty, !noisy.contains(text), text.count >= 2 {
                    return DeviceAlert(title: "设备异常，已暂停", detail: text)
                }
            }
        }

        // 2) 再看错误码：非 0 且带说明才算
        for (key, raw) in data {
            let lower = key.lowercased()
            guard lower.contains("error") || lower.contains("fault") || lower.contains("abnormal") else { continue }
            if let number = raw as? NSNumber, number.intValue == 0 { continue }
            if let text = raw as? String {
                let value = clean(text)
                if value.isEmpty || value == "0" || noisy.contains(value) { continue }
                if lower.contains("code") {
                    return DeviceAlert(title: "设备异常，已暂停",
                                       detail: "故障码 \(value)，请联系商家或检查洗衣机门是否关紧")
                }
                return DeviceAlert(title: "设备异常，已暂停", detail: value)
            }
        }

        // 3) 兜底：任何键名带 status/pause/stop 且值为「可疑文案」
        for (key, raw) in data {
            let lower = key.lowercased()
            guard lower.contains("status") || lower.contains("pause") || lower.contains("stop") else { continue }
            guard let text = raw as? String else { continue }
            let value = clean(text)
            if value.count >= 4, !noisy.contains(value), value.rangeOfCharacter(from: .letters) != nil || value.count > 6 {
                return DeviceAlert(title: "设备状态", detail: value, isWarning: false)
            }
        }
        return nil
    }

    // MARK: - 工具

    /// 扫码结果可能是官方链接（`https://h5.qiekj.com/skip?…&NQT=…`），也可能是 `NQT=xxx&…` 或裸机器码。
    func normalizedCode(_ raw: String) -> String {
        PGProtocol.machineCode(from: raw)
    }
}
