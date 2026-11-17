import Foundation

@MainActor
final class AppStore: ObservableObject {
    // MARK: - 状态

    @Published private(set) var settings = Settings()
    @Published private(set) var user: PGUser?
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
        log("扫码 \(cleaned) → goodsId \(goodsId)")
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
            deviceId: data.text("imei")
        )
        device = detail
        log("设备：\(detail.name)（\(detail.subtitle)）")

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

    func placeOrder(sku: PGSku) async -> Bool {
        guard let detail = device else {
            errorMessage = "先选一台洗衣机"
            return false
        }
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
        log("下单成功 orderId=\(orderId)，取支付串")

        await loadPayOptions(detail)
        let preferred = payOptions.first(where: { $0.isDefault })?.type ?? settings.payType
        let outcome = await requestPrePay(orderNo: orderId, preferred: preferred)
        busyText = ""
        if outcome.walletPaid {
            lastPrepayError = nil
            pending = nil
            persistPending()
            noticeMessage = "已用钱包余额付掉 \(orderId)"
            log("钱包余额支付成功 \(orderId)")
            await refreshOrders()
            return true
        }
        guard let picked = outcome.picked else {
            lastPrepayError = outcome.detail
            errorMessage = "订单已创建（\(orderId)），但取支付串失败：\(outcome.detail)"
            pending = PendingPayment(orderId: orderId,
                                     goodsId: detail.goodsId,
                                     skuId: sku.skuId,
                                     skuName: sku.name,
                                     price: sku.price,
                                     machineName: detail.name,
                                     orgName: detail.orgName,
                                     payType: settings.payType,
                                     prepayParam: "",
                                     createdAt: Date())
            persistPending()
            await refreshOrders()
            return false
        }
        pending = PendingPayment(orderId: orderId,
                                 goodsId: detail.goodsId,
                                 skuId: sku.skuId,
                                 skuName: sku.name,
                                 price: sku.price,
                                 machineName: detail.name,
                                 orgName: detail.orgName,
                                 payType: picked.payType,
                                 prepayParam: picked.param,
                                 createdAt: Date())
        lastPrepayError = nil
        persistPending()
        log("支付串已就绪（\(picked.param.count) 字符，payType=\(picked.payType)）")
        await refreshOrders()
        return true
    }

    func reopenPrepay() async {
        guard let current = pending else { return }
        busyText = "重新取支付串…"
        if payOptions.isEmpty, let detail = device {
            await loadPayOptions(detail)
        }
        let outcome = await requestPrePay(orderNo: current.orderId, preferred: current.payType)
        busyText = ""
        if outcome.walletPaid {
            pending = nil
            persistPending()
            lastPrepayError = nil
            noticeMessage = "已用钱包余额付掉 \(current.orderId)"
            await refreshOrders()
            return
        }
        guard let picked = outcome.picked else {
            lastPrepayError = outcome.detail
            errorMessage = outcome.detail
            return
        }
        pending?.prepayParam = picked.param
        pending?.payType = picked.payType
        lastPrepayError = nil
        persistPending()
        noticeMessage = "已取到\(PGProtocol.payTitle(picked.payType))支付串（\(picked.param.count) 字符）"
    }

    /// 依次试几条支付渠道，把每一次的原始 code/msg 都记进日志。
    /// 服务端对「渠道没开通 / 订单状态不对」只回一句 msg，不同网点开通的渠道也不一样，
    /// 所以这里不猜，直接挨个问一遍，拿到第一个有串的就用。
    struct PrePayOutcome {
        var picked: (payType: Int, param: String)?
        var detail: String
        /// 钱包余额已经直接扣掉了（不需要二维码）。
        var walletPaid: Bool = false
    }

    /// 问服务端这台机器开了哪些渠道。prePay 的 `payTypeList` 只在渠道缺失时才出现，
    /// 而且会对未开通的渠道回 code=0 + 空串，所以必须单独问一次。
    func loadPayOptions(_ detail: PGDeviceDetail) async {
        let response = await client.availablePayTypes(goodsId: detail.goodsId,
                                                      shopId: detail.shopId,
                                                      orgId: detail.orgId,
                                                      imei: detail.deviceId,
                                                      categoryCode: detail.categoryCode)
        let options = response.payOptions
        if response.ok, !options.isEmpty {
            payOptions = options
            let text = options.map { "\($0.type)=\($0.title)\($0.isDefault ? "（默认）" : "")" }
                .joined(separator: "、")
            log("这台机器可用支付方式 \(options.count) 种：\(text)")
        } else {
            payOptions = []
            log("可用支付方式查询失败：code=\(response.code) \(response.message)")
        }
    }

    func requestPrePay(orderNo: String, preferred: Int) async -> PrePayOutcome {
        var types: [Int] = [preferred]
        if let fallback = payOptions.first(where: { $0.isDefault })?.type,
           !types.contains(fallback) {
            types.append(fallback)
        }
        for option in payOptions where !types.contains(option.type) {
            types.append(option.type)
        }
        for candidate in [PGProtocol.payTypeAlipay, PGProtocol.payTypeWeChat,
                          PGProtocol.payTypeWallet, 15] where !types.contains(candidate) {
            types.append(candidate)
        }
        var notes: [String] = []
        lastPrepayRaw = ""
        for type in types {
            let response = await client.prePay(orderNo: orderNo, payType: type)
            let title = PGProtocol.payTitle(type)
            if response.ok {
                let data = response.dataObject ?? [:]
                let param = PGProtocol.deepPayParam(in: data)
                if param.isEmpty {
                    let list = response.payTypeList
                    let listText = list.isEmpty ? "" : "（服务端只开了 payType \(list.map(String.init).joined(separator: "/"))）"
                    let note = "\(title)（payType=\(type)）→ code=0 但没有支付串\(listText)"
                    notes.append(note)
                    lastPrepayRaw = "payType=\(type)\n\(response.body)"
                    log("取支付串 \(note)")
                    log("原始响应：\(String(response.body.prefix(1200)))")
                    if type == PGProtocol.payTypeWallet {
                        let wallet = await client.walletPay(orderNo: orderNo)
                        if wallet.ok {
                            log("钱包余额直接扣款成功：\(wallet.message)")
                            return PrePayOutcome(picked: nil,
                                                 detail: notes.joined(separator: "；"),
                                                 walletPaid: true)
                        }
                        let walletNote = "钱包扣款 → code=\(wallet.code) \(wallet.message)"
                        notes.append(walletNote)
                        lastPrepayRaw = "walletPay\n\(wallet.body)"
                        log(walletNote)
                        log("原始响应：\(String(wallet.body.prefix(1200)))")
                    }
                } else {
                    lastPrepayRaw = ""
                    log("取支付串成功：\(title)（payType=\(type)）\(param.count) 字符")
                    return PrePayOutcome(picked: (type, param),
                                         detail: notes.joined(separator: "；"))
                }
            } else {
                let note = "\(title)（payType=\(type)）→ code=\(response.code) \(response.message)"
                notes.append(note)
                lastPrepayRaw = "payType=\(type)\n\(response.body)"
                log("取支付串 \(note)")
                log("原始响应：\(String(response.body.prefix(1200)))")
                if response.isUnauthorized {
                    return PrePayOutcome(picked: nil, detail: "登录已失效，请重新登录后再试")
                }
            }
        }
        return PrePayOutcome(picked: nil, detail: notes.joined(separator: "\n"))
    }

    /// 在待支付面板里切换支付宝 / 微信：拿同一个订单号重新取一次支付串。
    /// 返回非 nil 表示失败原因，交给支付面板直接弹出来（挂在这个页面上，用户才看得见）。
    @discardableResult
    func switchPayType(_ type: Int) async -> String? {
        guard var current = pending else { return "没有待支付订单" }
        guard current.payType != type else { return nil }
        busyText = "切换为\(PGProtocol.payTitle(type))…"
        if type == PGProtocol.payTypeWallet {
            let wallet = await client.walletPay(orderNo: current.orderId)
            busyText = ""
            if wallet.ok {
                pending = nil
                persistPending()
                log("钱包余额支付成功 \(current.orderId)")
                noticeMessage = "已用钱包余额付掉 \(current.orderId)"
                await refreshOrders()
                return nil
            }
            log("钱包扣款失败 → code=\(wallet.code) \(wallet.message)")
            let balance = (user?.balance ?? "").trimmingCharacters(in: .whitespaces)
            return "钱包扣款失败：\(wallet.friendlyMessage)（当前余额 \(balance.isEmpty ? "未知" : "¥" + balance)）"
        }
        let prepay = await client.prePay(orderNo: current.orderId, payType: type)
        busyText = ""
        guard prepay.ok else {
            log("切换支付方式失败 → code=\(prepay.code) \(prepay.message)")
            return "切换为\(PGProtocol.payTitle(type))失败：\(prepay.friendlyMessage)"
        }
        let data = prepay.dataObject ?? [:]
        let param = PGProtocol.deepPayParam(in: data)
        current.payType = type
        current.prepayParam = param
        pending = current
        persistPending()
        log("支付方式切换为 \(PGProtocol.payTitle(type))，支付串 \(param.count) 字符")
        if param.isEmpty {
            return "服务端没有返回\(PGProtocol.payTitle(type))支付串（可能这个渠道没开通）。可以切回支付宝，或点「重新取支付串」再试。"
        }
        return nil
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

    // MARK: - 工具

    /// 扫码结果可能是链接，也可能是 `NQT=xxx&…`，这里取出机器码。
    func normalizedCode(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if let url = URL(string: text), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                let name = item.name.uppercased()
                if (name == "NQT" || name == "IMEI" || name == "SN"), let value = item.value, !value.isEmpty {
                    return value
                }
            }
        }
        let separators = CharacterSet(charactersIn: "&?; ")
        for pair in text.components(separatedBy: separators) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = parts[0].uppercased()
                if key == "NQT" || key == "IMEI" || key == "SN" {
                    return String(parts[1])
                }
            }
        }
        return text
    }
}
