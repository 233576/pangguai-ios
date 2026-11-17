"""从 APK 的 dex 里抽可读字符串并筛出协议相关的内容。

dex 里的字符串常量是明文存放的（加密壳之外），所以直接扫可打印 ASCII 段就够了。
目的：把我们自己推出来的接口清单，跟官方实现在对齐一次，尤其是：
  - /pay/unify/prePay 前后还传了什么
  - payType 的取值集合
  - /goods/scan/v2 的真实参数名
  - 签名串里 appSecret 附近的拼法
"""

import argparse
import io
import os
import re
import sys
import zipfile

PRINTABLE = re.compile(rb"[\x20-\x7e]{4,}")

FILTERS = [
    "prePay", "pay/unify", "appSecret", "goods/", "trade/", "order/",
    "user/", "common/", "scan", "payType", "qiekj", "token", "channel",
    "Version", "sign", "prepayParam", "orderNo", "NQT", "IMEI",
]


def strings_of(blob, min_len=4):
    out = []
    for m in re.finditer(rb"[\x20-\x7e]{%d,}" % min_len, blob):
        try:
            out.append(m.group().decode("ascii"))
        except Exception:
            pass
    return out


def collect(apk, only=None, pattern=""):
    z = zipfile.ZipFile(apk)
    names = [n for n in z.namelist() if n.endswith(".dex")]
    if only:
        names = [n for n in names if only in n]
    rx = re.compile(pattern) if pattern else None
    for name in names:
        blob = z.read(name)
        seen = set()
        for s in strings_of(blob):
            if s in seen:
                continue
            seen.add(s)
            if rx:
                if rx.search(s):
                    print(f"{name}\t{s}")
                continue
            if any(f in s for f in FILTERS):
                print(f"{name}\t{s}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apk")
    ap.add_argument("--dex", default="", help="只看某个 dex，比如 classes11")
    ap.add_argument("--re", default="", help="自定义正则")
    args = ap.parse_args()
    if not os.path.exists(args.apk):
        sys.exit(f"没有这个文件：{args.apk}")
    collect(args.apk, args.dex or None, args.re)


if __name__ == "__main__":
    main()
