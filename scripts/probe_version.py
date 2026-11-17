import hashlib
import json
import sys
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


def call(path, fields, version, version_code, token=''):
    import time
    ts = str(int(time.time() * 1000))
    body = dict(fields)
    if token:
        body['token'] = token
    data = urllib.parse.urlencode(body).encode()
    ua = ('QEUser/%s (%s; build:%s; iOS 18.5; userChannel:%s; version:%s)'
          % (version, PKG, version_code, CHANNEL, version))
    req = urllib.request.Request(BASE + path, data=data, method='POST')
    req.add_header('Content-Type', 'application/x-www-form-urlencoded;charset=UTF-8')
    req.add_header('Authorization', token)
    req.add_header('Version', version)
    req.add_header('channel', CHANNEL)
    req.add_header('phoneBrand', 'iPhone')
    req.add_header('deviceId', 'ios')
    req.add_header('timestamp', ts)
    req.add_header('sign', sign(path, token, ts, version))
    req.add_header('User-Agent', ua)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read().decode('utf-8', 'replace')
    except Exception as exc:  # noqa: BLE001
        return 'ERR %s' % exc


def main():
    versions = sys.argv[1:] or ['1.143.0', '1.147.0', '1.150.0', '1.155.0', '1.160.0', '2.0.0', '4.0.0']
    for v in versions:
        text = call('/goods/latestUsed', [('categoryCode', 'wash')], v, '290')
        print('%-9s %s' % (v, text[:220]))
        try:
            obj = json.loads(text)
            if obj.get('code') not in (-1,):
                print('   → 版本 %s 通过版本校验（code=%s）' % (v, obj.get('code')))
                break
        except Exception:
            pass


if __name__ == '__main__':
    main()
