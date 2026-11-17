"""找出 /payChannelRoute/prePay 到底要哪些参数。

思路：这个接口把「参数校验」放在「登录校验」之前，所以
  - 缺参数 → code=1 msg=must not be null / must not be blank
  - 参数齐了 → code=2 msg=未登录（我们没 token）
"=> 「出现 未登录」就是这套参数过关了。用它当判定信号，逐个加参数做贪心搜索。
"""

import hashlib
import itertools
import json
import time
import urllib.parse
import urllib.request

BASE = "https://userapi.qiekj.com"
SECRET = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="
CHANNEL = "android_app"
PKG = "com.qiekj.user"
VERSION = "1.143.0"
BUILD = "290"

CANDIDATES = [
    ("orderNo", "TESTORDER0001"),
    ("orderId", "TESTORDER0001"),
    ("tradeNo", "TESTORDER0001"),
    ("payType", "13"),
    ("channelCode", "alipay"),
    ("payScene", "1"),
    ("paySource", "1"),
    ("payAmount", "0.01"),
    ("sourceType", "1"),
    ("tradeType", "1"),
    ("appId", "2018072460764274"),
    ("returnUrl", "https://userapi.qiekj.com/"),
    ("subject", "洗衣机"),
    ("goodsId", "1"),
    ("orgId", "1"),
    ("payChannel", "1"),
    ("routeType", "1"),
]


def sign(path, token, ts):
    raw = "appSecret=%s&channel=%s&timestamp=%s&token=%s&version=%s&%s" % (
        SECRET, CHANNEL, ts, token, VERSION, path)
    return hashlib.sha256(raw.encode()).hexdigest()


def post(path, fields, token=""):
    ts = str(int(time.time() * 1000))
    body = dict(fields)
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
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8", "replace"))
    except Exception as exc:  # noqa: BLE001
        return {"code": 0, "msg": "ERR %s" % exc}


def probe(fields):
    obj = post("/payChannelRoute/prePay", fields)
    return obj.get("code"), str(obj.get("msg"))


def main():
    print("baseline:", probe([]))
    chosen = []
    changed = True
    while changed:
        changed = False
        for name, value in CANDIDATES:
            if any(c[0] == name for c in chosen):
                continue
            trial = chosen + [(name, value)]
            code, msg = probe(trial)
            if code != 1:
                print("+ %-12s → code=%s msg=%s   ← 参数够了" % (name, code, msg))
                print("FINAL:", trial)
                return
            if "must not be null" not in msg and "must not be blank" not in msg:
                print("+ %-12s → code=%s msg=%s" % (name, code, msg))
        # 一次没进展就两两组合试
        remaining = [(n, v) for n, v in CANDIDATES if not any(c[0] == n for c in chosen)]
        for (n1, v1), (n2, v2) in itertools.combinations(remaining, 2):
            code, msg = probe([(n1, v1), (n2, v2)])
            if code != 1:
                print("+ %s & %s → code=%s msg=%s" % (n1, n2, code, msg))
                print("FINAL:", [(n1, v1), (n2, v2)])
                return
        print("两两组合也没突破，参数名不在候选里")
        return


if __name__ == "__main__":
    main()
