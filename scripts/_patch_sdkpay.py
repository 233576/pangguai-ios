import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\PaySheet.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    private func openPayTarget() {
        let plan = handoff
        if !plan.schemes.isEmpty {
            openSchemes(plan.schemes, index: 0)
            return
        }
'''
new = '''    private func openPayTarget() {
        // 微信 App 支付参数：只有 OpenSDK 的 PayReq 能验签通过，
        // 拼 weixin://wap/pay 会被微信判「支付验证签名失败」。
        if payType == PGProtocol.payTypeWeChat {
            let fields = PGProtocol.payFields(current.prepayParam)
            if WeChatPay.parse(fields) != nil {
                WeChatPay.pay(fields) { ok, reason in
                    if !ok {
                        alertMessage = reason.isEmpty
                            ? "微信没有接受这次支付请求，可以换余额或用另一台手机扫码。"
                            : reason + "（也可以换余额，或点「复制支付串」发我）"
                    }
                }
                return
            }
        }

        let plan = handoff
        if !plan.schemes.isEmpty {
            openSchemes(plan.schemes, index: 0)
            return
        }
'''

assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('patched')
