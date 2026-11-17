import Foundation
import UIKit

/// 胖乖生活（userapi.qiekj.com）洗衣机协议常量与签名。
///
/// sign = SHA256("appSecret=..&channel=..&timestamp=..&token=..&version=..&<path>")
enum PGProtocol {
    static let base = "https://userapi.qiekj.com"
    static let appSecret = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="
    static let appVersion = "1.143.0"
    static let versionCode = "290"
    static let pkg = "com.qiekj.user"
    static let channel = "android_app"

    /// 洗衣机分类码：`/goods/latestUsed` 只认这个值。
    static let categoryCode = "wash"

    /// 洗衣机支持的渠道：2 余额（`/pay/unify/pay` 直接扣）、13 支付宝、32 微信。
    /// 具体这台机器开了哪些，看 `/pay/ticket/getAvailablePayTypeList`。
    static let payTypeWallet = 2
    static let payTypeAlipay = 13
    static let payTypeWeChat = 32

    static func payTitle(_ payType: Int) -> String {
        switch payType {
        case payTypeWeChat: return "微信支付"
        case payTypeAlipay, 15: return "支付宝"
        case payTypeWallet: return "余额支付"
        default: return "支付方式 \(payType)"
        }
    }

    /// 支付串藏在 `data` 的哪一层都可能，整棵 JSON 树翻一遍找最像支付串的那个值。
    static let payParamKeys = [
        "prepayParam", "payParam", "payParams", "payInfo", "payInfoStr", "payInfoJson",
        "orderString", "orderStr", "prepayString", "payParamStr", "payData", "payContent",
        "mweb_url", "mwebUrl", "h5_url", "h5Url", "code_url", "codeUrl", "payUrl", "pay_url"
    ]

    static func deepPayParam(in object: Any?) -> String {
        guard let object = object else { return "" }
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "111111" else { return "" }
            return trimmed
        }
        if let array = object as? [Any] {
            for element in array {
                let found = deepPayParam(in: element)
                if !found.isEmpty { return found }
            }
            return ""
        }
        guard let dict = object as? [String: Any] else { return "" }
        for key in payParamKeys {
            if let value = dict[key] {
                let found = deepPayParam(in: value)
                if !found.isEmpty { return found }
            }
        }
        for (_, value) in dict {
            if value is [String: Any] || value is [Any] {
                let found = deepPayParam(in: value)
                if !found.isEmpty { return found }
            }
        }
        return ""
    }

    /// 一条支付串要怎么交给对应 App：可能直接是 scheme、可能是 H5 地址、可能是一段扫码串、
    /// 也可能是微信 App 支付参数（没有 SDK 就调不起来，只能提示）。
    struct PayHandoff {
        var scheme: URL?
        var web: URL?
        var qr: String?
        var isWechatAppParam = false
        var note: String = ""

        var canOpen: Bool { scheme != nil || web != nil }
        var showQR: Bool { !(qr ?? "").isEmpty }
    }

    static func handoff(param: String, payType: Int) -> PayHandoff {
        var result = PayHandoff()
        let raw = param.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            result.note = "服务端没有返回支付串"
            return result
        }

        // 微信 App 支付参数：noncestr / appid / partnerid / prepayid / paySign / timestamp
        if let dict = jsonObject(raw) {
            func text(_ keys: [String]) -> String {
                for key in keys {
                    if let value = dict[key] as? String, !value.isEmpty { return value }
                    if let value = dict[key] as? NSNumber { return value.stringValue }
                }
                return ""
            }
            let mweb = text(["mweb_url", "mwebUrl"])
            let h5 = text(["h5_url", "h5Url", "payUrl", "pay_url", "url"])
            let codeURL = text(["code_url", "codeUrl"])
            let prepayid = text(["prepayid", "prepayId", "prepay_id"])
            let partnerid = text(["partnerid", "partnerId"])
            let appid = text(["appid", "appId"])
            let paySign = text(["paySign", "sign"])

            if !codeURL.isEmpty { result.qr = codeURL }
            if !mweb.isEmpty, let url = URL(string: mweb) { result.web = url }
            else if !h5.isEmpty, let url = URL(string: h5) { result.web = url }
            if !prepayid.isEmpty, !partnerid.isEmpty, !appid.isEmpty, !paySign.isEmpty {
                result.isWechatAppParam = true
                result.note = "这是微信 App 支付参数，需要微信 SDK 才能直接拉起；"
                    + "已把参数复制到剪贴板，可在官方 App 里粘贴或改用余额。"
            }
            if result.qr == nil && result.web == nil && !result.isWechatAppParam {
                result.note = "支付串里没有可用的跳转信息"
            }
            return result
        }

        if raw.hasPrefix("weixin://") || raw.hasPrefix("wxp://") {
            result.scheme = URL(string: raw)
            return result
        }
        if raw.lowercased().hasPrefix("http") {
            result.web = URL(string: raw)
            if payType == payTypeWeChat || payType == payTypeAlipay {
                result.qr = raw
            }
            return result
        }
        if raw.hasPrefix("{") || raw.hasPrefix("[") {
            result.note = "支付串格式无法识别"
            return result
        }

        // 支付宝 orderString / 普通串：走支付宝收银台 scheme + 二维码
        switch payType {
        case payTypeAlipay, 15:
            let encoded = Crypto.formEncode(raw)
            result.scheme = URL(string: "alipays://platformapi/startapp?appId=20000125&orderSuffix=\(encoded)")
            result.qr = result.scheme?.absoluteString ?? raw
        case payTypeWeChat:
            result.qr = raw
            result.note = "微信返回的是原始串，先用微信「扫一扫」扫下面的二维码"
        default:
            result.qr = raw
        }
        return result
    }

    static func jsonObject(_ raw: String) -> [String: Any]? {
        guard raw.hasPrefix("{"), let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 充值走官方 H5。真正的充值页是 `buyGold`（通用小票充值，只需 shopId），
    /// `user/recharge/operatorInfo` 只是「运营商信息」展示页，会显示「暂无运营商信息」。
    static let h5Base = "https://h5.qiekj.com/"

    /// 充值页（通用小票）：`buyGold?shopId=..&token=..`
    static func rechargeURL(token: String, shopId: String) -> URL? {
        guard !token.isEmpty, !shopId.isEmpty else { return nil }
        var components = URLComponents(string: h5Base + "buyGold")
        components?.queryItems = [
            URLQueryItem(name: "shopId", value: shopId),
            URLQueryItem(name: "token", value: token)
        ]
        return components?.url
    }

    /// 官方「我的钱包」页：`pages/wallet/myWallet/myWallet?token=..`
    static func walletURL(token: String) -> URL? {
        guard !token.isEmpty else { return nil }
        var components = URLComponents(string: h5Base + "pages/wallet/myWallet/myWallet")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    /// 余额明细页：`pages/wallet/balanceDetail/balanceDetail?token=..`
    static func balanceDetailURL(token: String) -> URL? {
        guard !token.isEmpty else { return nil }
        var components = URLComponents(string: h5Base + "pages/wallet/balanceDetail/balanceDetail")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    static func userAgent() -> String {
        let system = UIDevice.current.systemVersion
        return "QEUser/\(appVersion) (\(pkg); build:\(versionCode); iOS \(system); "
            + "userChannel:\(channel); version:\(appVersion))"
    }

    static func timestamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }

    static func requestSign(path: String, token: String, timestamp: String) -> String {
        let raw = "appSecret=" + appSecret
            + "&channel=" + channel
            + "&timestamp=" + timestamp
            + "&token=" + token
            + "&version=" + appVersion
            + "&" + path
        return Crypto.sha256Hex(raw)
    }

    /// 官方二维码长这样：
    /// `https://h5.qiekj.com/skip?Company=qiekj&CommunicateType=1&Ver=4&NQT=c13d3b8d-…`
    /// 官方 H5（`pages_skip` chunk）就是把这个 URL 的 query 原样作为 `/goods/scan/v2` 的表单字段，
    /// 所以这里也按同样方式拆：保留 NQT / Company / CommunicateType / Ver / keepUsing，其余忽略。
    static func scanFields(from raw: String) -> [(String, String)] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed: Set<String> = ["NQT", "COMPANY", "COMMUNICATETYPE", "VER", "KEEPUSING"]
        var result: [(String, String)] = []
        var seen = Set<String>()

        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                let key = item.name
                let upper = key.uppercased()
                guard allowed.contains(upper), !seen.contains(upper) else { continue }
                guard let value = item.value, !value.isEmpty else { continue }
                seen.insert(upper)
                result.append((key, value))
            }
        }

        if result.isEmpty {
            // 手输的裸机器码、或 `NQT=xxx&…` 这类非 URL 串
            let separators = CharacterSet(charactersIn: "&?; ")
            for pair in text.components(separatedBy: separators) {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 {
                    let upper = parts[0].uppercased()
                    guard allowed.contains(upper), !seen.contains(upper) else { continue }
                    seen.insert(upper)
                    result.append((String(parts[0]), String(parts[1])))
                }
            }
        }

        if !seen.contains("NQT"), !text.isEmpty, !text.lowercased().hasPrefix("http") {
            // 没有任何已知键：整串当机器码（手输 NQT）
            return [("NQT", text)]
        }
        return result
    }

    /// 从二维码/粘贴内容里取机器码本身，仅用于界面展示与日志。
    static func machineCode(from raw: String) -> String {
        let fields = scanFields(from: raw)
        for field in fields where field.0.uppercased() == "NQT" {
            return field.1
        }
        return fields.first?.1 ?? ""
    }
}

/// 统一响应包装。code == 0 为成功；2 / 401 表示未登录。
struct PGResponse {
    var httpStatus: Int = 0
    var body: String = ""
    var json: [String: Any] = [:]
    var transportError: String = ""

    var failed: Bool { !transportError.isEmpty }

    var code: Int {
        if let n = json["code"] as? NSNumber { return n.intValue }
        if let s = json["code"] as? String, let v = Int(s) { return v }
        return failed ? -1 : -999
    }

    var message: String {
        if failed { return transportError }
        if let m = json["msg"] as? String, !m.isEmpty { return m }
        return body.isEmpty ? "服务端没有返回内容" : String(body.prefix(200))
    }

    var dataObject: [String: Any]? { json["data"] as? [String: Any] }

    var dataArray: [[String: Any]]? { json["data"] as? [[String: Any]] }

    /// 服务端文案有几处会误导人，这里翻译成能照做的说法。
    /// 最典型：/goods/scan/v2 在 token 为空时回 `版本过低，请升级APP后再使用`，
    /// 实际与版本无关（换任何版本号都一样，带上任意非空 token 就恢复正常）。
    var friendlyMessage: String {
        let text = message
        if code == -1 && (text.contains("版本过低") || text.contains("升级")) {
            return "登录状态缺失，请先登录手机号账号再扫码"
        }
        if text.contains("设备未绑定") {
            return "这台机器没有在平台上绑定商家，暂时不能用（故障码 4000）"
        }
        return text
    }

    var ok: Bool { code == 0 }

    var isUnauthorized: Bool {
        if code == 2 || code == 401 { return true }
        let m = message
        return m.contains("未登录") || m.contains("登录已过期") || m.contains("登录过期")
            || m.contains("请重新登录") || m.contains("token失效") || m.contains("授权失效")
    }

    /// code 2128：上一笔没付款，把新订单挡住了，data 里带订单号。
    var unpaidBlockOrderId: String? {
        guard code == 2128 else { return nil }
        guard let obj = dataObject else { return nil }
        if let id = obj["incompleteOrderId"] as? String, !id.isEmpty { return id }
        if let no = obj["incompleteOrderNo"] as? String, !no.isEmpty { return no }
        return nil
    }

    /// `/pay/ticket/getAvailablePayTypeList` 的 `data` 数组。
    var payOptions: [PayOption] {
        guard let array = dataArray else { return [] }
        return array.compactMap { row -> PayOption? in
            let type = row.intValue("payType", -1)
            guard type > 0 else { return nil }
            return PayOption(type: type,
                             name: row.text("payTypeName"),
                             isDefault: row.intValue("defaultFlag", 0) == 1)
        }
    }

    /// prePay 的 `data.payTypeList`（渠道没开通时服务端会在这里回可用的数字数组）。
    var payTypeList: [Int] {
        guard let obj = dataObject, let list = obj["payTypeList"] as? [Any] else { return [] }
        return list.compactMap { item in
            if let n = item as? NSNumber { return n.intValue }
            if let s = item as? String { return Int(s) }
            return nil
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func text(_ key: String) -> String {
        if let v = self[key] as? String { return v }
        if let v = self[key] as? NSNumber { return v.stringValue }
        return ""
    }

    func intValue(_ key: String, _ fallback: Int = 0) -> Int {
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String, let v = Int(s) { return v }
        return fallback
    }

    func boolValue(_ key: String) -> Bool {
        if let b = self[key] as? Bool { return b }
        if let n = self[key] as? NSNumber { return n.boolValue }
        return false
    }
}
