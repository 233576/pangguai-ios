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
    /// 胖乖小程序 appid（抓自 h5.qiekj.com/skip 的 JSAPI 签名）。
    /// 微信 prepayParam 里不带 appid，拉起 weixin://wap/pay 时必须补上，否则报「appid 参数不正确」。
    static let wechatMiniAppId = "wxd1eab8ed00ec3c5b"
    static let payTypeWeChat = 31          // 抓包实证：prePay 用 31 才回真实 prepayParam
    static let payTypeWeChatLegacy = 32    // 旧渠道列表里出现的值，做兼容

    static func payTitle(_ payType: Int) -> String {
        switch payType {
        case payTypeWeChat, payTypeWeChatLegacy: return "微信支付"
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
    /// 也可能是微信 App 支付参数（prepayid 那一套 —— 没有 SDK 就用 `weixin://wap/pay` 试试）。
    struct PayHandoff {
        var schemes: [URL] = []
        var web: URL?
        var qr: String?
        var isWechatAppParam = false
        var note: String = ""

        var canOpen: Bool { !schemes.isEmpty || web != nil }
        var showQR: Bool { !(qr ?? "").isEmpty }
    }

    /// 支付串可能是 JSON，也可能是 `k=v&k=v` 拼串，统一拍平成字典。
    static func payFields(_ raw: String) -> [String: String] {
        if let object = jsonObject(raw) {
            var out: [String: String] = [:]
            for (key, value) in object {
                if let text = value as? String, !text.isEmpty {
                    out[key] = text
                } else if let number = value as? NSNumber {
                    out[key] = number.stringValue
                }
            }
            if !out.isEmpty { return out }
        }
        var out: [String: String] = [:]
        for pair in raw.components(separatedBy: CharacterSet(charactersIn: "&;,")) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \"{}"))
            guard !key.isEmpty, key.count < 40 else { continue }
            let value = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"{} "))
            out[key] = value.removingPercentEncoding ?? value
        }
        return out
    }

    static func firstValue(_ fields: [String: String], _ keys: [String]) -> String {
        for key in keys {
            if let value = fields[key], !value.isEmpty { return value }
        }
        // 微信/支付宝大小写不统一，兜底做一次忽略大小写匹配
        let lowered = keys.map { $0.lowercased() }
        for (key, value) in fields where lowered.contains(key.lowercased()) {
            if !value.isEmpty { return value }
        }
        return ""
    }

    /// 微信 App 支付参数 → 微信客户端的 `weixin://wap/pay` 入口。
    /// 官方 H5 支付就是这么把参数交给微信的，App 支付的 sign 与 H5 的 sign 算法不同，
    /// 所以这里把几种常见字段组合都试一遍（能通一种就够）。
    static func wechatSchemes(_ fields: [String: String]) -> [URL] {
        let package = firstValue(fields, ["package", "packageValue"])
        var prepay = firstValue(fields, ["prepayid", "prepayId", "prepay_id"])
        if prepay.isEmpty, package.hasPrefix("prepay_id=") {
            prepay = String(package.dropFirst("prepay_id=".count))
        }
        let sign = firstValue(fields, ["sign", "paySign", "pay_sign"])
        guard !prepay.isEmpty, !sign.isEmpty else { return [] }
        var appid = firstValue(fields, ["appid", "appId", "app_id"])
        if appid.isEmpty { appid = wechatMiniAppId }
        let nonce = firstValue(fields, ["noncestr", "nonceStr", "nonce_str"])
        let stamp = firstValue(fields, ["timestamp", "timeStamp", "time_stamp"])
        let partner = firstValue(fields, ["partnerid", "partnerId", "mch_id"])
        let signType = firstValue(fields, ["signType", "sign_type"])

        var variants: [[String: String]] = []
        // 小程序/JSAPI 支付参数：package 里就带 prepay_id，sign 是 HMAC-SHA256
        variants.append([
            "appid": appid, "noncestr": nonce, "package": package.isEmpty ? "Sign=WXPay" : package,
            "prepayid": prepay, "timestamp": stamp, "sign": sign, "signType": signType
        ])
        // 小程序 JSAPI 形态：package 直接是 prepay_id=xxx，不带 signType
        variants.append([
            "appid": appid, "noncestr": nonce, "package": package,
            "prepayid": prepay, "timestamp": stamp, "sign": sign
        ])
        // App 支付参数：另带 partnerid
        variants.append([
            "appid": appid, "noncestr": nonce, "package": package.isEmpty ? "Sign=WXPay" : package,
            "partnerid": partner, "prepayid": prepay, "timestamp": stamp, "sign": sign, "signType": signType
        ])
        // 不带 appid 的兜底（微信会从 prepay_id 反查商户）
        variants.append([
            "prepayid": prepay, "package": package.isEmpty ? "Sign=WXPay" : package,
            "noncestr": nonce, "timestamp": stamp, "sign": sign
        ])

        var result: [URL] = []
        for variant in variants {
            let query = variant
                .filter { !$0.value.isEmpty }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(Crypto.formEncode($0.value))" }
                .joined(separator: "&")
            if let url = URL(string: "weixin://wap/pay?" + query), !result.contains(url) {
                result.append(url)
            }
        }
        return result
    }

    static func handoff(param: String, payType: Int) -> PayHandoff {
        var result = PayHandoff()
        let raw = param.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            result.note = "服务端没有返回支付串"
            return result
        }

        let fields = payFields(raw)
        if !fields.isEmpty {
            let mweb = firstValue(fields, ["mweb_url", "mwebUrl", "mweburl"])
            let h5 = firstValue(fields, ["h5_url", "h5Url", "payUrl", "pay_url", "url", "link"])
            let codeURL = firstValue(fields, ["code_url", "codeUrl", "codeurl", "qr_code", "qrCode"])
            let ticket = firstValue(fields, ["ticket", "businessTicket"])

            if !codeURL.isEmpty { result.qr = codeURL }
            if !mweb.isEmpty, let url = URL(string: mweb) { result.web = url }
            else if !h5.isEmpty, let url = URL(string: h5) { result.web = url }

            if payType == payTypeWeChat || payType == payTypeWeChatLegacy {
                let wap = wechatSchemes(fields)
                if !wap.isEmpty {
                    result.schemes = wap
                    result.isWechatAppParam = true
                    result.note = "微信 App 支付参数：已生成 weixin://wap/pay 跳转，"
                        + "点「打开微信付款」试试；不行就用微信扫下面的码，或换余额。"
                }
                if !ticket.isEmpty, let url = URL(string: "weixin://dl/business/?t=" + ticket) {
                    result.schemes.append(url)
                }
            }

            if result.qr == nil && result.web == nil && result.schemes.isEmpty {
                if let url = URL(string: raw), url.scheme != nil { result.schemes = [url] }
            }
            if result.qr == nil && result.web == nil && result.schemes.isEmpty {
                result.note = "支付串里没有可用的跳转信息"
            }
            return result
        }

        if raw.hasPrefix("weixin://") || raw.hasPrefix("wxp://") {
            if let url = URL(string: raw) {
                result.schemes = [url]
                result.qr = raw
            }
            return result
        }
        if raw.lowercased().hasPrefix("http") {
            result.web = URL(string: raw)
            if payType == payTypeWeChat || payType == payTypeWeChatLegacy || payType == payTypeAlipay {
                result.qr = raw
            }
            return result
        }
        if raw.hasPrefix("{") || raw.hasPrefix("[") {
            result.note = "支付串格式无法识别"
            return result
        }

        switch payType {
        case payTypeAlipay, 15:
            let encoded = Crypto.formEncode(raw)
            if let url = URL(string: "alipays://platformapi/startapp?appId=20000125&orderSuffix=" + encoded) {
                result.schemes = [url]
                result.qr = url.absoluteString
            }
        case payTypeWeChat, payTypeWeChatLegacy:
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
