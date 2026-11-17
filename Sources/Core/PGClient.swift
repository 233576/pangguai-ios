import Foundation

/// 胖乖生活洗衣机接口。所有请求都是 POST 表单，签名见 `PGProtocol.requestSign`。
final class PGClient {
    var token: String
    private let session: URLSession

    init(token: String = "") {
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - 底层

    func post(_ path: String, _ fields: [(String, String)] = []) async -> PGResponse {
        var payload = fields
        if !token.isEmpty {
            payload.append(("token", token))
        }

        let stamp = PGProtocol.timestamp()
        let sign = PGProtocol.requestSign(path: path, token: token, timestamp: stamp)

        var request = URLRequest(url: URL(string: PGProtocol.base + path)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(PGProtocol.appVersion, forHTTPHeaderField: "Version")
        request.setValue(PGProtocol.channel, forHTTPHeaderField: "channel")
        request.setValue("iPhone", forHTTPHeaderField: "phoneBrand")
        request.setValue("ios", forHTTPHeaderField: "deviceId")
        request.setValue(stamp, forHTTPHeaderField: "timestamp")
        request.setValue(sign, forHTTPHeaderField: "sign")
        request.setValue(PGProtocol.userAgent(), forHTTPHeaderField: "User-Agent")
        request.httpBody = Crypto.formBody(payload)

        var response = PGResponse()
        do {
            let (data, urlResponse) = try await session.data(for: request)
            if let http = urlResponse as? HTTPURLResponse {
                response.httpStatus = http.statusCode
            }
            response.body = String(data: data, encoding: .utf8) ?? ""
            if let object = try? JSONSerialization.jsonObject(with: data),
               let dict = object as? [String: Any] {
                response.json = dict
            }
        } catch {
            let ns = error as NSError
            response.transportError = "网络错误：\(ns.localizedDescription)（\(ns.code)）"
        }
        return response
    }

    // MARK: - 账号

    /// 发短信验证码。template 用 "1"（登录场景）。
    func sendCode(phone: String) async -> PGResponse {
        await post("/common/sms/sendCode", [
            ("phone", phone),
            ("template", "1")
        ])
    }

    /// 验证码登录（胖乖的 /user/reg 同时承担注册与登录）。
    func login(phone: String, verify: String) async -> PGResponse {
        await post("/user/reg", [
            ("channel", PGProtocol.channel),
            ("phone", phone),
            ("verify", verify)
        ])
    }

    func userInfo() async -> PGResponse {
        await post("/user/info")
    }

    func balance() async -> PGResponse {
        await post("/user/balance")
    }

    // MARK: - 洗衣机

    /// 最近用过的洗衣机（categoryCode=wash）。
    func latestDevices() async -> PGResponse {
        await post("/goods/latestUsed", [("categoryCode", PGProtocol.categoryCode)])
    }

    /// 扫码得到的机器码 → goodsId。
    /// 注意：服务端在 token 为空时对该接口回 `code=-1 版本过低，请升级APP后再使用`，
    /// 与版本号无关，先说清楚再发请求。
    func scan(code: String) async -> PGResponse {
        if token.isEmpty {
            var response = PGResponse()
            response.body = "{\"code\":-100,\"msg\":\"请先登录后再扫码\"}"
            response.json = ["code": -100, "msg": "请先登录后再扫码"]
            return response
        }
        return await post("/goods/scan/v2", [("NQT", code)])
    }

    func deviceDetail(goodsId: String) async -> PGResponse {
        await post("/goods/normal/details", [("goodsId", goodsId)])
    }

    func skus(goodsId: String) async -> PGResponse {
        await post("/goods/normal/skus", [("goodsId", goodsId)])
    }

    // MARK: - 下单与支付

    /// 洗衣下单。promotions / items 两个字段是 JSON 字符串。
    func createTrade(orgId: String, goodsId: String, skuId: String) async -> PGResponse {
        let promotions = "[{\"assetId\":\"0\",\"oldPromotionId\":\"3482\","
            + "\"orgId\":\"\(orgId)\",\"promotionId\":\"0\",\"promotionType\":\"4\"}]"
        let items = "[{\"amount\":\"1\",\"goodsId\":\"\(goodsId)\",\"num\":\"1\","
            + "\"skuId\":\"\(skuId)\",\"soldType\":\"1\"}]"
        return await post("/trade/create", [
            ("promotions", promotions),
            ("items", items)
        ])
    }

    /// 取支付串（payType 13 = 支付宝）。
    func prePay(orderNo: String, payType: Int) async -> PGResponse {
        await post("/pay/unify/prePay", [
            ("orderNo", orderNo),
            ("payType", String(payType))
        ])
    }

    /// 查这笔单付了没。data 为 true / false。
    func payStatus(orderNo: String, payType: Int) async -> PGResponse {
        await post("/order/pay_status", [
            ("orderNo", orderNo),
            ("payType", String(payType))
        ])
    }

    // MARK: - 订单

    func orders(page: Int = 1, pageSize: Int = 30) async -> PGResponse {
        await post("/order/list", [
            ("page", String(page)),
            ("pageSize", String(pageSize)),
            ("orderStatus", "")
        ])
    }

    func orderDetail(orderId: String) async -> PGResponse {
        await post("/order/detail", [("orderId", orderId)])
    }

    /// 撤销未启动的订单（不扣费）。
    func cancelOrder(orderId: String) async -> PGResponse {
        await post("/order/cancel", [("orderId", orderId)])
    }
}
