import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Core\PGProtocol.swift'
t = io.open(p, encoding='utf-8').read()

start = t.index('    /// 一条支付串要怎么交给对应 App')
end = t.index('    static func jsonObject(_ raw: String) -> [String: Any]?')

new = '''    /// 一条支付串要怎么交给对应 App：可能直接是 scheme、可能是 H5 地址、可能是一段扫码串、
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
            let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \\"{}"))
            guard !key.isEmpty, key.count < 40 else { continue }
            let value = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\\"{} "))
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
        let prepay = firstValue(fields, ["prepayid", "prepayId", "prepay_id"])
        let sign = firstValue(fields, ["sign", "paySign", "pay_sign"])
        guard !prepay.isEmpty, !sign.isEmpty else { return [] }
        let appid = firstValue(fields, ["appid", "appId", "app_id"])
        let nonce = firstValue(fields, ["noncestr", "nonceStr", "nonce_str"])
        let package = firstValue(fields, ["package", "packageValue"])
        let stamp = firstValue(fields, ["timestamp", "timeStamp", "time_stamp"])
        let partner = firstValue(fields, ["partnerid", "partnerId", "mch_id"])

        var variants: [[String: String]] = []
        variants.append([
            "appid": appid, "noncestr": nonce, "package": package.isEmpty ? "Sign=WXPay" : package,
            "prepayid": prepay, "timestamp": stamp, "sign": sign
        ])
        variants.append([
            "appid": appid, "noncestr": nonce, "package": package.isEmpty ? "Sign=WXPay" : package,
            "partnerid": partner, "prepayid": prepay, "timestamp": stamp, "sign": sign
        ])
        variants.append([
            "prepayid": prepay, "package": package.isEmpty ? "Sign=WXPay" : package,
            "noncestr": nonce, "timestamp": stamp, "sign": sign, "appid": appid
        ])

        var result: [URL] = []
        for variant in variants {
            let query = variant
                .filter { !$0.value.isEmpty }
                .sorted { $0.key < $1.key }
                .map { "\\($0.key)=\\(Crypto.formEncode($0.value))" }
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

            if payType == payTypeWeChat {
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
            if payType == payTypeWeChat || payType == payTypeAlipay {
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
        case payTypeWeChat:
            result.qr = raw
            result.note = "微信返回的是原始串，先用微信「扫一扫」扫下面的二维码"
        default:
            result.qr = raw
        }
        return result
    }

'''

t = t[:start] + new + t[end:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('patched, lines =', t.count('\n') + 1)
