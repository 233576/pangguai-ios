import hashlib, json, sys, time, urllib.parse, urllib.request

BASE = "https://userapi.qiekj.com"
SECRET = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="
VERSION = "1.143.0"
CHANNEL = "android_app"
UA = "QEUser/%s (com.qiekj.user; build:290; iOS 18.5; userChannel:android_app; version:%s)" % (VERSION, VERSION)


def sign(path, token, ts):
    raw = "appSecret=%s&channel=%s&timestamp=%s&token=%s&version=%s&%s" % (SECRET, CHANNEL, ts, token, VERSION, path)
    return hashlib.sha256(raw.encode()).hexdigest()


def call(path, fields, token="", extra_headers=None):
    ts = str(int(time.time() * 1000))
    body = dict(fields)
    if token:
        body["token"] = token
    data = urllib.parse.urlencode(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
    req.add_header("Authorization", token)
    req.add_header("Version", VERSION)
    req.add_header("channel", CHANNEL)
    req.add_header("phoneBrand", "iPhone")
    req.add_header("deviceId", "ios")
    req.add_header("timestamp", ts)
    req.add_header("sign", sign(path, token, ts))
    req.add_header("User-Agent", UA)
    for k, v in (extra_headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except Exception as exc:
        return getattr(exc, "code", -1), str(exc)


NQT = "c13d3b8d-d6ff-427c-9c32-597a72a814c5"
QUERY = {"Company": "qiekj", "CommunicateType": "1", "Ver": "4", "NQT": NQT}

cases = [
    ("scan/v2 仅 NQT（无 token）", "/goods/scan/v2", {"NQT": NQT}, ""),
    ("scan/v2 仅 NQT（假 token）", "/goods/scan/v2", {"NQT": NQT}, "deadbeefdeadbeefdeadbeefdeadbeef"),
    ("scan/v2 全 query（假 token）", "/goods/scan/v2", QUERY, "deadbeefdeadbeefdeadbeefdeadbeef"),
    ("scan/v2 大写 NQT（假 token）", "/goods/scan/v2", {"NQT": NQT.upper()}, "deadbeefdeadbeefdeadbeefdeadbeef"),
    ("scan/v2 key+value（假 token）", "/goods/scan/v2", {"key": "NQT", "value": NQT}, "deadbeefdeadbeefdeadbeefdeadbeef"),
    ("scan/v2 SN（假 token）", "/goods/scan/v2", {"SN": NQT}, "deadbeefdeadbeefdeadbeefdeadbeef"),
]

for name, path, fields, token in cases:
    status, body = call(path, fields, token)
    print("%-32s -> %s %s" % (name, status, body[:220]))
