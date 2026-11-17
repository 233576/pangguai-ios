import Foundation
import UIKit
import WechatOpenSDK

/// 微信 App 支付（`PayReq`）。
///
/// 为什么需要它：服务端 `/pay/unify/prePay` 在 payType=32 时返回的是微信 **App 支付参数**
/// （partnerId / prepayId / nonceStr / timeStamp / package / sign），不是 URL。
/// 这些参数的 sign 是「App 支付」算法的结果，拼成 `weixin://wap/pay` 会被微信判为
/// 「支付验证签名失败」，只有走 OpenSDK 的 `PayReq` 才能正确验签。
///
/// 注意：bundle id 是 com.pangguai.ios，与官方 App 不同。微信支付侧只认 appid + sign，
/// 不校验 bundle id；回跳依赖 URL Scheme `wx<appid>`，这个 scheme 运行时才知道，
/// 所以支付回调可能收不到 —— 付完款回到 App 用「我付好了，查状态」兜底即可。
enum WeChatPay {
    private static var registeredAppId = ""

    /// 微信要求 universalLink 非空；这里给胖乖官方的 H5 域名，实际不会真的走 Universal Link。
    static let universalLink = "https://h5.qiekj.com/"

    static func register(appId: String) {
        guard !appId.isEmpty, appId != registeredAppId else { return }
        let ok = WXApi.registerApp(appId, universalLink: universalLink)
        if ok { registeredAppId = appId }
    }

    struct Params {
        var appId: String
        var partnerId: String
        var prepayId: String
        var nonceStr: String
        var timeStamp: UInt32
        var package: String
        var sign: String
    }

    static func parse(_ fields: [String: String]) -> Params? {
        func pick(_ keys: [String]) -> String {
            for key in keys {
                if let value = fields[key], !value.isEmpty { return value }
            }
            let lowered = keys.map { $0.lowercased() }
            for (key, value) in fields where lowered.contains(key.lowercased()) {
                if !value.isEmpty { return value }
            }
            return ""
        }

        let appId = pick(["appid", "appId", "app_id"])
        let partnerId = pick(["partnerid", "partnerId", "mch_id"])
        let prepayId = pick(["prepayid", "prepayId", "prepay_id"])
        let nonceStr = pick(["noncestr", "nonceStr", "nonce_str"])
        let stamp = pick(["timestamp", "timeStamp", "time_stamp"])
        let package = pick(["package", "packageValue"])
        let sign = pick(["sign", "paySign", "pay_sign"])

        guard !partnerId.isEmpty, !prepayId.isEmpty, !sign.isEmpty else { return nil }
        let seconds = UInt32(stamp) ?? UInt32(Date().timeIntervalSince1970)
        return Params(appId: appId,
                      partnerId: partnerId,
                      prepayId: prepayId,
                      nonceStr: nonceStr,
                      timeStamp: seconds,
                      package: package.isEmpty ? "Sign=WXPay" : package,
                      sign: sign)
    }

    static func canPay(_ fields: [String: String]) -> Bool {
        parse(fields) != nil && WXApi.isWXAppInstalled()
    }

    /// 返回 (是否成功交给微信, 失败原因)。
    static func pay(_ fields: [String: String],
                    completion: @escaping (Bool, String) -> Void) {
        guard let params = parse(fields) else {
            completion(false, "支付参数不完整（缺 partnerid / prepayid / sign）")
            return
        }
        guard WXApi.isWXAppInstalled() else {
            completion(false, "这台设备没装微信")
            return
        }
        register(appId: params.appId)

        let req = PayReq()
        req.partnerId = params.partnerId
        req.prepayId = params.prepayId
        req.nonceStr = params.nonceStr
        req.timeStamp = params.timeStamp
        req.package = params.package
        req.sign = params.sign

        WXApi.sendReq(req) { ok in
            DispatchQueue.main.async {
                completion(ok, ok ? "" : "微信没有接受这次支付请求")
            }
        }
    }
}
