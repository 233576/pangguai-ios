import hashlib
import time
import urllib.parse
import urllib.request

BASE = 'https://userapi.qiekj.com'
SECRET = 'nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o='
CHANNEL = 'android_app'
PKG = 'com.qiekj.user'


def sign(path, token, ts, version):
    raw = 'appSecret=%s&channel=%s&timestamp=%s&token=%s&version=%s&%s' % (
        SECRET, CHANNEL, ts, token, version, path)
    return hashlib.sha256(raw.encode()).hexdigest()


def call(path, fields, version='1.143.0', version_code='290', token='', extra_headers=None):
    ts = str(int(time.time() * 1000))
    body = dict(fields)
    if token:
        body['token'] = token
    data = urllib.parse.urlencode(body).encode()
    ua = ('QEUser/%s (%s; build:%s; iOS 18.5; userChannel:%s; version:%s)'
          % (version, PKG, version_code, CHANNEL, version))
    req = urllib.request.Request(BASE + path, data=data, method='POST')
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Authorization': token,
        'Version': version,
        'channel': CHANNEL,
        'phoneBrand': 'iPhone',
        'deviceId': 'ios',
        'timestamp': ts,
        'sign': sign(path, token, ts, version),
        'User-Agent': ua,
    }
    if extra_headers:
        headers.update(extra_headers)
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode('utf-8', 'replace')
    except Exception as exc:  # noqa: BLE001
        return 'ERR %s' % exc
    try:
        import json
        obj = json.loads(text)
        return 'code=%s msg=%s data=%s' % (obj.get('code'), obj.get('msg'), str(obj.get('data'))[:120])
    except Exception:
        return text[:200]


PATHS = [
    '/goods/scan',
    '/goods/scan/v1',
    '/goods/scan/v2',
    '/goods/scan/v3',
    '/goods/normal/scan',
    '/goods/qrCode/scan',
    '/goods/qrcode/info',
    '/goods/normal/queryByCode',
    '/goods/normal/details',
]

if __name__ == '__main__':
    print('== 路径探测（版本 1.143.0）==')
    for p in PATHS:
        print('%-28s %s' % (p, call(p, [('NQT', 'TESTCODE'), ('goodsId', '1')])))

    print('\n== scan/v2 头部变体 ==')
    variants = [
        ('versionCode 头', {'versionCode': '9999'}),
        ('appVersion 头', {'appVersion': '1.143.0', 'versionCode': '290'}),
        ('version 1.200.0', None),
        ('Version 421 + build 421', None),
    ]
    for name, extra in variants:
        if name == 'version 1.200.0':
            print('%-28s %s' % (name, call('/goods/scan/v2', [('NQT', 'TESTCODE')], version='1.200.0')))
        elif name == 'Version 421 + build 421':
            print('%-28s %s' % (name, call('/goods/scan/v2', [('NQT', 'TESTCODE')],
                                           version='421', version_code='421')))
        else:
            print('%-28s %s' % (name, call('/goods/scan/v2', [('NQT', 'TESTCODE')], extra_headers=extra)))

    print('\n== 参数名变体 ==')
    for fields in (
        [('SN', 'TESTCODE')],
        [('IMEI', 'TESTCODE')],
        [('code', 'TESTCODE')],
        [('nqt', 'TESTCODE')],
        [('key', 'NQT'), ('value', 'TESTCODE')],
    ):
        print('%-40s %s' % (fields, call('/goods/scan/v2', fields)))
