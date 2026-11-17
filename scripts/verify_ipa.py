#!/usr/bin/env python3
"""检查未签名 ipa 的结构：Payload/*.app、Info.plist 关键字段、Mach-O 架构。"""
import plistlib
import struct
import sys
import zipfile

CPU_TYPES = {7: "i386", 0x01000007: "x86_64", 12: "arm", 0x0100000C: "arm64", 0x0200000C: "arm64_32"}


def main(path: str) -> int:
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        print(f"ipa: {path}")
        print(f"entries: {len(names)}")
        apps = sorted({n.split('/')[1] for n in names if n.startswith('Payload/') and n.count('/') >= 2})
        print(f"apps: {apps}")
        for app in apps:
            info_path = f"Payload/{app}/Info.plist"
            if info_path not in names:
                print(f"  ! {info_path} 缺失")
                continue
            info = plistlib.loads(zf.read(info_path))
            print(f"  {app}:")
            for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
                        "MinimumOSVersion", "CFBundleExecutable", "CFBundleDisplayName"):
                print(f"    {key} = {info.get(key)}")
            exe = info.get("CFBundleExecutable") or app.split('.')[0]
            exe_path = f"Payload/{app}/{exe}"
            if exe_path not in names:
                print(f"    ! 可执行文件 {exe_path} 缺失")
                continue
            data = zf.read(exe_path)
            magic = struct.unpack("<I", data[:4])[0]
            print(f"    可执行文件: {len(data)} 字节, magic=0x{magic:08x}")
            if magic in (0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF):
                print("    → FAT/Universal 二进制")
                n = struct.unpack(">I", data[4:8])[0]
                for i in range(n):
                    cputype, _sub, offset = struct.unpack(">III", data[8 + i * 20: 8 + i * 20 + 12])
                    print(f"      slice {i}: {CPU_TYPES.get(cputype, hex(cputype))} @ {offset}")
            else:
                cputype = struct.unpack("<I", data[4:8])[0]
                filetype = struct.unpack("<I", data[12:16])[0]
                print(f"    → {CPU_TYPES.get(cputype, hex(cputype))}, filetype={filetype} (2=MH_EXECUTE)")
        sig = [n for n in names if "_CodeSignature" in n]
        print(f"code signature entries: {len(sig)} (未签名应为 0)")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "dist/Pangguai-unsigned.ipa"))
