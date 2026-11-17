"""解密 lepao stopRun 真实报文，打印业务字段（用于设计 iOS 端）。"""
import base64
import io
import json
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _aes_cbc import _self_test, decrypt_b64  # noqa: E402

KEY = b'Wet2C8d34f62ndi3'
IV = b'K6iv85jBD8jgf32D'

PKT = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\bd\2422725977__ctbu-lepao-main\ctbu-lepao-main\stopRun_packet.json'


def main():
    print('aes selftest:', _self_test())
    data = json.load(io.open(PKT, encoding='utf-8'))
    for item in data:
        print('\n---', item.get('dir'), item.get('path'), 'flag=', item.get('flag'))
        if 'body_b64' not in item:
            continue
        body = base64.b64decode(item['body_b64']).decode('utf-8', 'replace')
        q = urllib.parse.parse_qs(body)
        enc = q.get('data', [''])[0]
        plain = decrypt_b64(KEY, IV, enc)
        print('明文长度', len(plain))
        try:
            obj = json.loads(plain)
        except Exception:
            print(plain[:1500])
            continue
        for k in sorted(obj):
            v = obj[k]
            s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
            print('  %-24s %s' % (k, s[:200]))


if __name__ == '__main__':
    main()
