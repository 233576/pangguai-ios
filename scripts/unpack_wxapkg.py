"""解包微信小程序包（.wxapkg），用于看清胖乖生活小程序真实调用哪些接口。

两种常见形态都吃：
  1) 手机端明文包：首字节 0xBE，结构 = 0xBE + 4(info1) + 4(indexLen) + 4(bodyLen) + 1(mark) + 4(count) + 索引项...
  2) PC 微信 / 新版加密包：文件头是 "V1MMWX"，需要 appid 做 PBKDF2 + AES-256-CBC 解密后再按上面结构解。

用法：
    python scripts/unpack_wxapkg.py 包路径.wxapkg [--appid wxXXXXXXXXXXXXXXXX] [-o 输出目录]
    python scripts/unpack_wxapkg.py 多个包所在目录 -o out

解完会顺手把所有 .js/.wxml/.json 里出现的 userapi.qiekj.com / 接口路径 / appSecret 抓一遍，
直接把结果打到屏幕上——这一屏就是我们写客户端要的规格。
"""

import argparse
import hashlib
import os
import re
import struct
import sys
import zlib

try:
    from Crypto.Cipher import AES  # pycryptodome，可选
except Exception:  # pragma: no cover
    AES = None


def decrypt_pc(data, appid):
    """PC 微信加密包：V1MMWX 头 + AES-256-CBC + 单字节异或。"""
    if AES is None:
        raise SystemExit("这个包是加密的，需要 pycryptodome：pip install pycryptodome")
    body = data[6:]
    key = hashlib.pbkdf2_hmac("sha1", appid.encode(), b"saltiest", 1000, 32)
    iv = b"the iv: 16 bytes"
    plain = AES.new(key, AES.MODE_CBC, iv).decrypt(body)
    # 去掉 PKCS7 填充
    pad = plain[-1]
    if 0 < pad <= 16:
        plain = plain[:-pad]
    # 经典实现里再和 0x36 异或一次
    return bytes(b ^ 0x36 for b in plain)


def parse_index(data):
    """返回 [(name, offset, size)]，offset 相对数据区起点。"""
    if not data or data[0] != 0xBE:
        raise ValueError("不是明文 wxapkg（首字节不是 0xBE）")
    index_len = struct.unpack(">I", data[5:9])[0]
    p = 14
    count = struct.unpack(">I", data[p:p + 4])[0]
    p += 4
    entries = []
    for _ in range(count):
        name_len = struct.unpack(">I", data[p:p + 4])[0]
        p += 4
        name = data[p:p + name_len].decode("utf-8", "replace")
        p += name_len
        off = struct.unpack(">I", data[p:p + 4])[0]
        p += 4
        size = struct.unpack(">I", data[p:p + 4])[0]
        p += 4
        entries.append((name, off, size))
    return entries, 14 + index_len


def safe_join(root, name):
    name = name.lstrip("/").replace("\\", "/")
    parts = [x for x in name.split("/") if x not in ("", ".", "..")]
    return os.path.join(root, *parts)


def unpack(path, outdir, appid=""):
    raw = open(path, "rb").read()
    if raw[:6] == b"V1MMWX" or raw[:2] == b"\x00\x00":
        if not appid:
            raise SystemExit(f"{os.path.basename(path)} 是加密包，需要 --appid")
        raw = decrypt_pc(raw, appid)
    entries, base = parse_index(raw)
    written = 0
    for name, off, size in entries:
        blob = raw[base + off: base + off + size]
        target = safe_join(outdir, name)
        os.makedirs(os.path.dirname(target) or outdir, exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(blob)
        written += 1
    print(f"{os.path.basename(path)}: {written} 个文件 → {outdir}")
    return outdir


PATTERNS = [
    (re.compile(r"https?://[A-Za-z0-9_.\-]*(?:qiekj|pangguai)[A-Za-z0-9_.\-/:?#=&%]*"), "胖乖域名"),
    (re.compile(r"[\"'`](/?(?:user|goods|trade|pay|order|common|shower|message)/[a-zA-Z0-9_/.]{2,60})[\"'`]"), "接口路径"),
    (re.compile(r"appSecret[\"'\s:=]+([A-Za-z0-9+/=]{20,})"), "appSecret"),
    (re.compile(r"payType[\"'\s:=]+(\d{1,3})"), "payType"),
    (re.compile(r"channel[\"'\s:=]+([a-z_]{4,20})"), "channel"),
]


def scan(root):
    hits = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if not fn.endswith((".js", ".json", ".wxml", ".wxss", ".wxs")):
                continue
            p = os.path.join(dirpath, fn)
            try:
                text = open(p, encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            for rx, label in PATTERNS:
                for m in rx.finditer(text):
                    value = m.group(1) if m.groups() else m.group(0)
                    hits.setdefault(label, {}).setdefault(value, 0)
                    hits[label][value] += 1
    for label, values in hits.items():
        print(f"\n## {label}")
        for value, count in sorted(values.items(), key=lambda kv: -kv[1])[:40]:
            print(f"  {value}  ×{count}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", help=".wxapkg 文件或包含多个包的目录")
    ap.add_argument("-o", "--out", default="unpacked")
    ap.add_argument("--appid", default="")
    args = ap.parse_args()

    targets = []
    if os.path.isdir(args.target):
        for dirpath, _d, files in os.walk(args.target):
            targets += [os.path.join(dirpath, f) for f in files if f.endswith(".wxapkg")]
    else:
        targets = [args.target]
    if not targets:
        raise SystemExit("没找到 .wxapkg")

    for path in targets:
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            unpack(path, os.path.join(args.out, name), args.appid)
        except Exception as exc:
            print(f"!! {path}: {exc}", file=sys.stderr)
    scan(args.out)


if __name__ == "__main__":
    main()
