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


def raw_scan(token_value, send_field=True, path='/goods/scan/v2'):
    ts = str(int(time.time() * 1000))
    body = {'NQT': 'TESTCODE'}
    if send_field:
        body['token'] = token_value
    data = urllib.parse.urlencode(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method='POST')
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Authorization': token_value,
        'Version': '1.143.0',
        'channel': CHANNEL,
        'phoneBrand': 'iPhone',
        'deviceId': 'ios',
        'timestamp': ts,
        'sign': sign(path, token_value, ts, '1.143.0'),
        'User-Agent': 'QEUser/1.143.0 (%s; build:290; iOS 18.5; userChannel:%s; version:1.143.0)' % (PKG, CHANNEL),
    }
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read().decode('utf-8', 'replace')[:200]
    except Exception as exc:  # noqa: BLE001
        return 'ERR %s' % exc


if __name__ == '__main__':
    print('A 空 token（header+body 都为空串）:', raw_scan(''))
    print('B token=0 占位                 :', raw_scan('0'))
    print('C 空 header、不发 body token   :', raw_scan('', send_field=False))
