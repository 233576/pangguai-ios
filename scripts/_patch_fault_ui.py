import io

base = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources'

# ---------- Models.swift: DeviceAlert ----------
p = base + r'\Core\Models.swift'
t = io.open(p, encoding='utf-8').read()

anchor = '''// MARK: - 支付渠道'''
add = '''// MARK: - 设备异常提示

/// 官方 App 在订单页会顶一条「设备异常，已暂停 / 请确认洗衣机门是否关紧」。
/// 服务端不同网点返回的字段名不一致，所以这里用「字段名启发式 + 文案原样透出」的方式，
/// 宁可少显示，也不伪造文案。
struct DeviceAlert: Equatable {
    var title: String
    var detail: String
    var isWarning: Bool = true
}

// MARK: - 支付渠道'''
assert anchor in t
t = t.replace(anchor, add, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('Models patched')

# ---------- AppStore.swift ----------
p = base + r'\Core\AppStore.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    /// 每秒跳动一次，驱动洗涤倒计时。只有界面里真的显示倒计时时才跑，省电。
    @Published private(set) var now = Date()'''
new = '''    /// 每秒跳动一次，驱动洗涤倒计时。只有界面里真的显示倒计时时才跑，省电。
    @Published private(set) var now = Date()
    /// 进行中订单的设备异常提示（服务端有就给，没有就是 nil）。
    @Published private(set) var deviceAlert: DeviceAlert?
    /// 最近一次 `/order/detail` 的原始响应，供「复制诊断信息」用。
    @Published private(set) var lastDetailRaw: String = ""

    private var lastDetailAt = Date.distantPast
    private var detailBusy = false'''
assert old in t
t = t.replace(old, new, 1)

# tick 里顺带轮询 detail
old2 = '''                self.now = Date()
                self.checkFinish()'''
new2 = '''                self.now = Date()
                self.checkFinish()
                if self.now.timeIntervalSince(self.lastDetailAt) > 25 {
                    Task { await self.refreshActiveDetail() }
                }'''
assert old2 in t
t = t.replace(old2, new2, 1)

# 新增刷新方法与解析
anchor2 = '''    // MARK: - 工具'''
add2 = '''    // MARK: - 设备异常

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
                                       detail: "故障码 \\(value)，请联系商家或检查洗衣机门是否关紧")
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

    // MARK: - 工具'''
assert anchor2 in t
t = t.replace(anchor2, add2, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('AppStore patched')
