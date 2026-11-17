import io

p = 'Sources/Core/WeChatPay.swift'
t = io.open(p, encoding='utf-8').read()
old = '''        guard WXApi.isWXAppInstalled() else {
            completion(false, "这台设备没装微信")
            return
        }
        register(appId: params.appId)'''
new = '''        register(appId: params.appId)'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('WeChatPay patched')

p2 = 'Sources/Views/PaySheet.swift'
s = io.open(p2, encoding='utf-8').read()
old2 = '''            if WeChatPay.parse(fields) != nil {
                WeChatPay.pay(fields) { ok, reason in
                    if !ok {
                        alertMessage = reason.isEmpty
                            ? "微信没有接受这次支付请求，可以换余额或用另一台手机扫码。"
                            : reason + "（也可以换余额，或点「复制支付串」发我）"
                    }
                }
                return
            }'''
new2 = '''            if WeChatPay.parse(fields) != nil {
                WeChatPay.pay(fields) { ok, reason in
                    guard !ok else { return }
                    // SDK 发不出去（常见：服务端 sign 绑了官方包名）就退回上一版能用的 weixin://wap/pay
                    let fallback = handoff.schemes
                    if !fallback.isEmpty {
                        openSchemes(fallback, index: 0)
                    } else {
                        alertMessage = reason.isEmpty
                            ? "微信没有接受这次支付请求，可以换余额或用另一台手机扫码。"
                            : reason + "（也可以换余额，或点「复制支付串」发我）"
                    }
                }
                return
            }'''
assert old2 in s
s = s.replace(old2, new2, 1)
io.open(p2, 'w', encoding='utf-8', newline='\n').write(s)
print('PaySheet patched')
