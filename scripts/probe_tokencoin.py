# -*- coding: utf-8 -*-
"""探测 tokenCoin/goods 与 order/createVirtualOrder 的参数与返回结构。"""
import hashlib
import json
import sys
import urllib.parse
import urllib.request

BASE = "https://userapi.qiekj.com"
SECRET = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="
CHANNEL = "android_app"
VERSION = "1.143.0"


def sign(path, token, ts):
    raw = ("appSecret=%s&channel=%s&timestamp=%s&token=%s&version=%s&%s"
           % (SECRET, CHANNEL, ts, token, VERSION, path))
    return hashlib.sha256(raw.encode()).hexdigest()


def post(path, fields, token=""):
    import time
    ts = str(int(time.time() * 1000))
    form = dict(fields)
    if token:
        form["token"] = token
    body = urllib.parse.urlencode(form).encode()
    req = urllib.request.Request(BASE + "/" + path, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
    req.add_header("Authorization", token)
    req.add_header("Version", VERSION)
    req.add_header("channel", CHANNEL)
    req.add_header("timestamp", ts)
    req.add_header("sign", sign(path, token, ts))
    req.add_header("phoneBrand", "iPhone")
    req.add_header("deviceId", "ios")
    req.add_header("User-Agent", "QEUser/1.143.0 (com.qiekj.user; build:290; iOS 18.5; userChannel:android_app; version:1.143.0)")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.read().decode("utf-8", "ignore")
    except Exception as exc:  # noqa: BLE001
        return "ERR %s" % exc


token = sys.argv[1] if len(sys.argv) > 1 else "deadbeefdeadbeefdeadbeefdeadbeef"
shop = sys.argv[2] if len(sys.argv) > 2 else "1"

for path, fields in [
    ("tokenCoin/goods", {"shopId": shop}),
    ("order/createVirtualOrder", {"shopId": shop, "goodsId": "1", "goodsType": "1", "Num": "10", "tokenCoinRewardId": "1"}),
    ("user/astrict/list", {}),
    ("shop/detail", {"shopId": shop}),
]:
    print("==", path, fields)
    print(post(path, fields, token)[:600])
    print()
