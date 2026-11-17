"""极简 DEX 读取器：把指定方法的常量字符串按出现顺序打印出来。

为什么要它：APK 里 dex 是明文的，但只按「全局字符串池」看，参数名和接口名混在一起
没法判断谁跟谁配对。这里直接读 class_data → code_item 的字节码，把某个方法体内
出现的 const-string 按顺序列出来，就能还原「这个请求到底拼了哪些字段」。

用法：
    python scripts/dex_methods.py pg\\inbox\\com.qiekj.user.apk --match prePay
    python scripts/dex_methods.py pg\\inbox\\com.qiekj.user.apk --match payChannelRoute --dex classes11
"""

import argparse
import struct
import sys
import zipfile


class Dex:
    def __init__(self, blob):
        self.data = blob
        (self.string_ids_size, self.string_ids_off,
         self.type_ids_size, self.type_ids_off,
         self.proto_ids_size, self.proto_ids_off,
         self.field_ids_size, self.field_ids_off,
         self.method_ids_size, self.method_ids_off,
         self.class_defs_size, self.class_defs_off) = struct.unpack_from("<12I", blob, 0x38)

    def u32(self, off):
        return struct.unpack_from("<I", self.data, off)[0]

    def uleb(self, off):
        result = 0
        shift = 0
        while True:
            byte = self.data[off]
            off += 1
            result |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return result, off
            shift += 7

    def string(self, idx):
        if idx >= self.string_ids_size:
            return ""
        off = self.u32(self.string_ids_off + idx * 4)
        _, off = self.uleb(off)          # utf16 length
        end = self.data.index(b"\x00", off)
        return self.data[off:end].decode("utf-8", "replace")

    def type_name(self, idx):
        if idx >= self.type_ids_size:
            return ""
        return self.string(self.u32(self.type_ids_off + idx * 4))

    def method(self, idx):
        off = self.method_ids_off + idx * 8
        class_idx, proto_idx, name_idx = struct.unpack_from("<HHI", self.data, off)
        return self.string(name_idx), self.type_name(class_idx)

    def class_data(self, class_def_off):
        class_idx, _, _, _, _, _, data_off, _static_values = struct.unpack_from("<8I", self.data, class_def_off)
        return self.type_name(class_idx), data_off

    def methods_of(self, class_def_off):
        """返回 [(method_name, code_off)]"""
        _, data_off = self.class_data(class_def_off)
        if data_off == 0:
            return []
        off = data_off
        static_fields, off = self.uleb(off)
        instance_fields, off = self.uleb(off)
        direct_methods, off = self.uleb(off)
        virtual_methods, off = self.uleb(off)
        out = []
        for _ in range(static_fields):
            _, off = self.uleb(off)
            _, off = self.uleb(off)
        for _ in range(instance_fields):
            _, off = self.uleb(off)
            _, off = self.uleb(off)
        for _ in range(direct_methods + virtual_methods):
            idx_diff, off = self.uleb(off)
            _, off = self.uleb(off)
            code_off, off = self.uleb(off)
            out.append((idx_diff, code_off))
        return out

    def const_strings(self, code_off):
        """线性扫 insns，抓 const-string / const-string/jumbo 的索引（启发式）。"""
        if code_off == 0:
            return []
        off = code_off
        registers, ins, outs, tries = struct.unpack_from("<4H", self.data, off)
        debug_off = self.u32(off + 8)
        insns_size = self.u32(off + 12)
        base = off + 16
        units = struct.unpack_from("<%dH" % insns_size, self.data, base)
        found = []
        i = 0
        while i < insns_size:
            unit = units[i]
            op = unit & 0xFF
            if op == 0x1A and i + 1 < insns_size:          # const-string vAA, string@BBBB
                found.append(units[i + 1])
                i += 2
                continue
            if op == 0x1B and i + 2 < insns_size:          # const-string/jumbo
                found.append(units[i + 1] | (units[i + 2] << 16))
                i += 3
                continue
            i += 1
        return [self.string(idx) for idx in found]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apk")
    ap.add_argument("--match", default="prePay", help="方法名/类名里包含这个字符串")
    ap.add_argument("--dex", default="", help="只看某个 dex")
    args = ap.parse_args()

    z = zipfile.ZipFile(args.apk)
    names = [n for n in z.namelist() if n.endswith(".dex")]
    if args.dex:
        names = [n for n in names if args.dex in n]

    needle = args.match.lower()
    for name in names:
        dex = Dex(z.read(name))
        for i in range(dex.class_defs_size):
            class_def_off = dex.class_defs_off + i * 32
            cls, _ = dex.class_data(class_def_off)
            if needle in cls.lower():
                print(f"\n### {name}  class {cls}")
                for method_idx_diff, code_off in dex.methods_of(class_def_off):
                    print(f"  (method index delta {method_idx_diff}, code_off {code_off})")
                continue
            for method_idx_diff, code_off in dex.methods_of(class_def_off):
                if code_off == 0:
                    continue
                strings = dex.const_strings(code_off)
                if not strings:
                    continue
                joined = " ".join(strings)
                if needle in joined.lower() or needle in cls.lower():
                    print(f"\n### {name}  {cls}  code_off={code_off}")
                    for s in strings:
                        print("   ", s)


if __name__ == "__main__":
    sys.exit(main())
