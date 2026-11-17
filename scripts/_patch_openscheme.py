import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\PaySheet.swift'
t = io.open(p, encoding='utf-8').read()

start = t.index('    private func openPayTarget() {')
end = t.index('    private func payWithWallet() async {')

new = '''    private func openPayTarget() {
        let plan = handoff
        if !plan.schemes.isEmpty {
            openSchemes(plan.schemes, index: 0)
            return
        }
        if let web = plan.web {
            webPayURL = web
            showingWebPay = true
            return
        }
        if plan.isWechatAppParam {
            UIPasteboard.general.string = current.prepayParam
            alertMessage = "这是微信 App 支付参数，weixin://wap/pay 没被系统接受。参数已复制到剪贴板，"
                + "可以换余额、换支付宝，或者用另一台手机扫二维码。"
            return
        }
        alertMessage = "没有可用的跳转方式，先用另一台手机扫码吧"
    }

    /// 依次尝试多个 scheme（微信 wap/pay 有几种字段组合，能通一种就够）。
    private func openSchemes(_ urls: [URL], index: Int) {
        guard index < urls.count else {
            UIPasteboard.general.string = current.prepayParam
            alertMessage = "系统没有接受任何一个\(PGProtocol.payTitle(payType))跳转链接。"
                + "支付串已复制到剪贴板；也可以换渠道，或用另一台手机扫码。"
            return
        }
        let url = urls[index]
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok {
                Task { @MainActor in
                    openSchemes(urls, index: index + 1)
                }
            }
        }
    }

'''

t = t[:start] + new + t[end:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('patched, lines =', t.count('\n') + 1)
