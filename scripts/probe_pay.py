"""探测支付相关接口的真实形态（不需要登录态就够了，看错误码就能区分）。

背景：App 里 /pay/unify/prePay 返回 code=0 但 prepayParam 是空的，说明这条老接口
可能已经不给支付宝/微信出参数了。官方 APK 里同时存在：
    pay/unify/prePay            老聚合
    payChannelRoute/prePay      新「支付渠道路由」
    payChannelRoute/afterPay
    payChannelRoute/againPay
    pay/unify/pay
因此先打一遍，看哪条是活的、要哪些参数、返回什么字段。

用法：
    python scripts/probe_pay.py                 # 全部候选 × 全部 payType
    python scripts/probe_pay.py --token XXX     # 带上真实 token（登录后从 App 日志拿）
"""

import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://userapi.qiekj.com"
SECRET = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="
CHANNEL = "android_app"
PKG = "com.qiekj.user"
VERSION = "1.143.0"
BUILD = "290"

PAY_PATHS = [
    "/pay/unify/prePay",
    "/payChannelRoute/prePay",
    "/pay/unify/pay",
    "/payChannelRoute/afterPay",
]

PAY_TYPES = ["13", "32", "2", "15"]


def sign(path, token, ts):
    raw = "appSecret=%s&channel=%s&timestamp=%s&token=%s&version=%s&%s" % (
        SECRET, CHANNEL, ts, token, VERSION, path)
    return hashlib.sha256(raw.encode()).hexdigest()


def post(path, fields, token=""):
    ts = str(int(time.time() * 1000))
    body = dict(fields)
    if token:
        body["token"] = token
    data = urllib.parse.urlencode(body).encode()
    ua = "QEUser/%s (%s; build:%s; iOS 18.5; userChannel:%s; version:%s)" % (
        VERSION, PKG, BUILD, CHANNEL, VERSION)
    req = urllib.request.Request(BASE + path, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
    req.add_header("Authorization", token)
    req.add_header("Version", VERSION)
    req.add_header("channel", CHANNEL)
    req.add_header("phoneBrand", "iPhone")
    req.add_header("deviceId", "ios")
    req.add_header("timestamp", ts)
    req.add_header("sign", sign(path, token, ts))
    req.add_header("User-Agent", ua)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:  # noqa: F821
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        return 0, "ERR %s" % exc


def brief(text, limit=260):
    try:
        obj = json.loads(text)
    except Exception:
        return text[:limit]
    data = obj.get("data")
    if isinstance(data, dict):
        keys = ", ".join(data.keys())
        return "code=%s msg=%s | data keys: %s" % (obj.get("code"), obj.get("msg"), keys)
    return "code=%s msg=%s | data=%s" % (obj.get("code"), obj.get("msg"), str(data)[:limit])


def main():
    token = ""
    if "--token" in sys.argv:
        token = sys.argv[sys.argv.index("--token") + 1]
    order = "--order" in sys.argv and sys.argv[sys.argv.index("--order") + 1] or "TESTORDER0001"

    print("token: %s" % ("(空)" if not token else token[:8] + "…"))
    for path in PAY_PATHS:
        for pay_type in PAY_TYPES:
            status, text = post(path, [("orderNo", order), ("payType", pay_type)], token)
            print("%-26s payType=%-3s HTTP %-3s %s" % (path, pay_type, status, brief(text)))


if __name__ == "__main__":
    main()
