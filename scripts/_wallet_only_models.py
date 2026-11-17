import io

p = 'Sources/Core/Models.swift'
t = io.open(p, encoding='utf-8').read()

pairs = [
    ("    var hasQR: Bool { !prepayParam.isEmpty }",
     "    var isSettled: Bool { prepayParam.isEmpty }"),
    ("""    var detail: String {
        switch type {
        case PGProtocol.payTypeWallet: return "余额扣款"
        case PGProtocol.payTypeWeChat: return "扫一扫付款"
        case PGProtocol.payTypeAlipay: return "扫码 / 跳转"
        default: return isDefault ? "默认" : ""
        }
    }""",
     """    var detail: String {
        if type == PGProtocol.payTypeWallet { return "余额扣款" }
        return isDefault ? "默认" : ""
    }"""),
    ("var payType: Int = PGProtocol.payTypeAlipay", "var payType: Int = PGProtocol.payTypeWallet"),
    ("?? PGProtocol.payTypeAlipay", "?? PGProtocol.payTypeWallet"),
]

for old, new in pairs:
    if old not in t:
        raise SystemExit('missing: ' + old[:50])
    t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('models patched')
