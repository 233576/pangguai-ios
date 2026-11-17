import Foundation

// MARK: - 账号

struct PGUser: Codable, Equatable {
    var phone: String = ""
    var balance: String = ""
    var hasVip: Bool = false

    var balanceText: String {
        balance.isEmpty ? "—" : "¥\(balance)"
    }
}

/// `/user/astrict/list` 一条受限（店铺）余额。
struct PGBalanceItem: Codable, Identifiable, Hashable {
    var remainCoin: String = ""
    var shopNames: String = ""
    var machineTypeNames: String = ""

    var id: String { shopNames + "|" + machineTypeNames }

    var amount: Double {
        Double(remainCoin.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    var amountText: String {
        remainCoin.isEmpty ? "—" : "¥\(remainCoin)"
    }
}

// MARK: - 设备

/// `/goods/latestUsed` 最近用过的一台洗衣机。
struct PGRecentDevice: Codable, Identifiable, Hashable {
    var goodsId: String
    var name: String
    var orgName: String
    var workStatus: Int

    var id: String { goodsId }

    var statusText: String {
        switch workStatus {
        case 10: return "空闲"
        case 20: return "使用中"
        default: return workStatus < 0 ? "—" : "状态 \(workStatus)"
        }
    }

    var isIdle: Bool { workStatus == 10 }
}

/// `/goods/normal/details` 洗衣机详情。
struct PGDeviceDetail: Codable, Equatable {
    var goodsId: String = ""
    var name: String = ""
    var orgName: String = ""
    var orgId: String = ""
    var shopId: String = ""
    var categoryCode: String = ""
    var brandName: String = ""
    var soldState: Int = 0
    var serviceTelephone: String = ""
    var deviceId: String = ""

    var subtitle: String {
        var parts: [String] = []
        if !orgName.isEmpty { parts.append(orgName) }
        if !brandName.isEmpty { parts.append(brandName) }
        return parts.joined(separator: " · ")
    }
}

/// `/goods/normal/skus` 可选套餐（洗涤时长 / 温度 …）。
struct PGSku: Codable, Identifiable, Hashable {
    var skuId: String
    var name: String
    var feature: String
    var price: String
    var unit: String
    var stockState: Int

    var id: String { skuId }

    var priceText: String {
        price.isEmpty ? "—" : "¥\(price)"
    }

    var available: Bool { stockState == 1 || stockState == 0 }
}

// MARK: - 订单

/// `/order/list` 一条订单。
struct PGOrder: Codable, Identifiable, Hashable {
    var id: String
    var orderNo: String
    var status: Int
    var createTime: String
    var payPrice: String
    var markPrice: String
    var machineName: String
    var shopName: String
    var functionName: String
    var minutes: Int

    var statusText: String {
        switch status {
        case 0: return "待支付"
        case 1: return "已支付"
        case 2: return "进行中"
        case 3: return "已完成"
        case 4: return "已取消"
        case 5: return "退款中"
        case 6: return "已退款"
        default: return "状态 \(status)"
        }
    }

    var isUnpaid: Bool { status == 0 }

    var amountText: String {
        if !payPrice.isEmpty { return "¥\(payPrice)" }
        if !markPrice.isEmpty { return "¥\(markPrice)" }
        return "—"
    }

    var title: String {
        if !machineName.isEmpty { return machineName }
        if !functionName.isEmpty { return functionName }
        return "洗衣机订单"
    }
}

// MARK: - 待支付订单（本地账本）

/// 洗衣机是「先付款后启动」。下单拿到 orderId，支付串要单独取一次并保存，
/// 进程被杀也能重新出码。
struct PendingPayment: Codable, Equatable {
    var orderId: String
    var goodsId: String
    var skuId: String
    var skuName: String
    var price: String
    var machineName: String
    var orgName: String
    var payType: Int
    var prepayParam: String
    var createdAt: Date

    var isSettled: Bool { prepayParam.isEmpty }
}

// MARK: - 支付渠道

/// 服务端 `/pay/ticket/getAvailablePayTypeList` 返回的一项。
/// 不同网点开通的渠道不一样，UI 只该列出真实开通的。
struct PayOption: Identifiable, Hashable {
    var type: Int
    var name: String
    var isDefault: Bool

    var id: Int { type }

    var title: String { name.isEmpty ? PGProtocol.payTitle(type) : name }

    var detail: String {
        if type == PGProtocol.payTypeWallet { return "余额扣款" }
        return isDefault ? "默认" : ""
    }
}

// MARK: - 设置

struct Settings: Codable, Equatable {
    var lastPhone: String = ""
    var autoRefresh: Bool = true
    var payType: Int = PGProtocol.payTypeWallet

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastPhone = (try? c.decode(String.self, forKey: .lastPhone)) ?? ""
        autoRefresh = (try? c.decode(Bool.self, forKey: .autoRefresh)) ?? true
        payType = (try? c.decode(Int.self, forKey: .payType)) ?? PGProtocol.payTypeWallet
    }
}
