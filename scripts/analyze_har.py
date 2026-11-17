"""把抓包结果（HAR 文件）里胖乖的请求整理成人能看的清单。

用途：下单流程里到底是哪一步返回了空支付串，一次看清。
支持：
  - Chrome / Safari / Charles / Proxyman 导出的 .har
  - HttpCanary 导出的 .har（同上）
  - 直接贴一条 curl 也行：--curl "curl 'https://...' -d 'a=1'"

用法：
    python scripts/analyze_har.py 抓包.har
    python scripts/analyze_har.py --curl "curl 'https://userapi.qiekj.com/pay/unify/prePay' -d 'orderNo=123&payType=13'"
"""

import argparse
import json
import re
import sys

HOST_HINT = ("qiekj", "pangguai", "gwifi", "100.100.9.2")
INTERESTING = ("prePay", "trade/create", "order/pay_status", "scan", "user/reg", "user/info")


def show_request(url, method, headers, body):
    print(f"\n=== {method} {url}")
    for key in ("Authorization", "Version", "channel", "timestamp", "sign", "deviceId", "phoneBrand"):
        for hk, hv in (headers or {}).items():
            if hk.lower() == key.lower():
                print(f"    {hk}: {hv}")
    if body:
        text = body if isinstance(body, str) else json.dumps(body, ensure_ascii=False)
        fields = dict(re.findall(r"([A-Za-z0-9_]+)=([^&]*)", text))
        if fields:
            for k, v in fields.items():
                shown = v if len(v) <= 120 else v[:120] + f"…({len(v)}字符)"
                print(f"    {k} = {shown}")
        else:
            print("    body:", text[:400])


def show_response(status, body):
    print(f"    ← HTTP {status}")
    if not body:
        return
    try:
        obj = json.loads(body)
    except Exception:
        print("    原文:", body[:300])
        return
    print(f"    code={obj.get('code')} msg={obj.get('msg')}")
    data = obj.get("data")
    if isinstance(data, dict):
        for k, v in data.items():
            shown = str(v)
            if len(shown) > 140:
                shown = shown[:140] + f"…({len(shown)}字符)"
            print(f"    data.{k} = {shown}")
    elif isinstance(data, list):
        print(f"    data: 数组，{len(data)} 项")
        if data and isinstance(data[0], dict):
            print("    首项键:", ", ".join(data[0].keys()))
    else:
        print("    data =", data)


def from_har(path):
    har = json.load(open(path, encoding="utf-8"))
    entries = har.get("log", {}).get("entries", [])
    print(f"HAR 共 {len(entries)} 条请求")
    shown = 0
    for entry in entries:
        req = entry.get("request", {})
        url = req.get("url", "")
        if not any(h in url for h in HOST_HINT):
            continue
        resp = entry.get("response", {})
        body = (req.get("postData") or {}).get("text", "")
        headers = {h.get("name"): h.get("value") for h in req.get("headers", [])}
        show_request(url, req.get("method", "?"), headers, body)
        show_response(resp.get("status"), (resp.get("content") or {}).get("text", ""))
        shown += 1
    if not shown:
        print("没有胖乖相关请求——抓包时记得让 App 的流量走代理（HTTPS 需要装证书）")


def from_curl(cmd):
    url = re.search(r"curl\s+'([^']+)'", cmd) or re.search(r'curl\s+"([^"]+)"', cmd)
    if not url:
        raise SystemExit("没解析出 URL")
    data = re.search(r"-d\s+'([^']*)'", cmd) or re.search(r'-d\s+"([^"]*)"', cmd)
    show_request(url.group(1), "POST", {}, data.group(1) if data else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("har", nargs="?")
    ap.add_argument("--curl", default="")
    args = ap.parse_args()
    if args.curl:
        from_curl(args.curl)
    elif args.har:
        from_har(args.har)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
