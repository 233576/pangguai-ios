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

    /// 支付宝主动支付。13 = 支付宝，15 = 支付宝免密，2 = 钱包，32 = 微信。
    static let payTypeAlipay = 13
    static let payTypeWallet = 2
    static let payTypeWeChat = 32

    static func payTitle(_ payType: Int) -> String {
        switch payType {
        case payTypeAlipay, 15: return "支付宝"
        case payTypeWeChat: return "微信支付"
        case payTypeWallet: return "钱包余额"
        default: return "在线支付"
        }
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

    /// 支付宝收银台入口，可直接放进二维码让支付宝「扫一扫」识别。
    static func alipayScheme(for orderString: String) -> URL? {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = orderString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "alipays://platformapi/startapp?appId=20000125&orderSuffix=\(encoded)")
    }

    /// 二维码里放的内容：
    /// 1. 已经是 scheme / http 链接 → 原样；
    /// 2. 支付宝 orderString（`app_id=…&sign=…`）→ 转成官方 scheme，扫码即可拉起收银台。
    static func qrContent(for param: String) -> String {
        let trimmed = param.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("alipays://") || lower.hasPrefix("alipayqr://") || lower.hasPrefix("http") {
            return trimmed
        }
        return alipayScheme(for: trimmed)?.absoluteString ?? trimmed
    }

    /// 依次尝试的跳转入口。
    static func paymentCandidates(for param: String) -> [URL] {
        let trimmed = param.trimmingCharacters(in: .whitespacesAndNewlines)
        var list: [URL] = []
        let lower = trimmed.lowercased()
        if lower.hasPrefix("alipays://") || lower.hasPrefix("alipayqr://") || lower.hasPrefix("http"),
           let url = URL(string: trimmed) {
            list.append(url)
        }
        if let scheme = alipayScheme(for: trimmed) {
            list.append(scheme)
            // 支付宝「扫一扫」入口：把上面那条 scheme 当二维码内容喂给它，
            // 装不上收银台 scheme 的老版本也能落到扫码页。
            let qrPayload = scheme.absoluteString
            let allowed = CharacterSet(charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            if let encodedQR = qrPayload.addingPercentEncoding(withAllowedCharacters: allowed),
               let qrScheme = URL(string: "alipayqr://platformapi/startapp?saId=10000007&qrcode=\(encodedQR)") {
                list.append(qrScheme)
            }
        }
        if let home = URL(string: "alipays://") {
            list.append(home)
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? trimmed
        if let web = URL(string: "https://openapi.alipay.com/gateway.do?\(encoded)") {
            list.append(web)
        }
        return list
    }

    // MARK: - 微信

    /// 把 prepayParam 解析成 JSON 对象（微信侧经常返回 JSON 字符串）。
    static func jsonObject(_ param: String) -> [String: Any]? {
        let trimmed = param.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 微信支付能放进二维码的地址：优先 native 支付码（code_url），
    /// 其次是 H5 支付链接（mweb_url），最后才原样返回。
    static func wechatQRText(for param: String) -> String {
        let trimmed = param.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("weixin://") || lower.hasPrefix("http") || lower.hasPrefix("wxp://") {
            return trimmed
        }
        if let obj = jsonObject(trimmed) {
            let qrKeys = ["code_url", "codeUrl", "codeurl", "qr_code", "qrCode", "qrurl", "qrUrl"]
            for key in qrKeys {
                if let value = obj[key] as? String, !value.isEmpty { return value }
            }
            let webKeys = ["mweb_url", "mwebUrl", "h5_url", "h5Url", "payUrl", "pay_url", "url"]
            for key in webKeys {
                if let value = obj[key] as? String, !value.isEmpty { return value }
            }
        }
        return trimmed
    }

    /// 微信侧跳转候选：先试支付串里的真实链接，最后退回「打开微信」。
    static func wechatCandidates(for param: String) -> [URL] {
        let text = wechatQRText(for: param)
        var list: [URL] = []
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           scheme == "weixin" || scheme == "wxp" || scheme == "https" || scheme == "http" {
            list.append(url)
        }
        if let app = URL(string: "weixin://") {
            list.append(app)
        }
        return list
    }

    /// 微信 App 支付串（appid/partnerid/prepayid/sign）无法用 URL 直接拉起，
    /// 只能提示用户走扫码；这里判断一下是不是这种形态。
    static func wechatNeedsNativeApp(param: String) -> Bool {
        guard let obj = jsonObject(param) else { return false }
        return obj["prepayid"] != nil || obj["partnerid"] != nil || obj["package"] != nil
    }

    /// 任意支付方式下二维码里应该放的内容。
    static func qrContent(for param: String, payType: Int) -> String {
        if payType == payTypeWeChat {
            return wechatQRText(for: param)
        }
        return qrContent(for: param)
    }

    /// 打开对应 App 的「扫一扫」页面（用户再从相册选刚保存的二维码）。
    /// 这条路比直接调起收银台稳得多：收银台入口各版本时常被废弃，扫一扫一直是受支持的入口。
    static func qrScanScheme(payType: Int) -> URL? {
        if payType == payTypeWeChat {
            return URL(string: "weixin://scanqrcode")
        }
        return URL(string: "alipays://platformapi/startapp?saId=10000007")
    }

    /// 能在 Safari 里打开的支付页。
    /// 微信 H5 支付（mweb_url）只有从浏览器发起，微信才会接管；支付宝可以退回网关页。
    static func safariPayURL(for param: String, payType: Int) -> URL? {
        let text = payType == payTypeWeChat ? wechatQRText(for: param) : qrContent(for: param)
        let lower = text.lowercased()
        if lower.hasPrefix("http"), let url = URL(string: text) { return url }
        if payType == payTypeWeChat { return nil }
        let encoded = param.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? param
        return URL(string: "https://openapi.alipay.com/gateway.do?\(encoded)")
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
