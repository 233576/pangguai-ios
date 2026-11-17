"""在所有 dex 的所有方法里找「包含某个字符串常量」的方法，并打印该方法内全部常量串。

用法：
    python scripts/dex_find_string.py pg/inbox/com.qiekj.user.apk "payChannelRoute"
"""
import sys
import zipfile

sys.path.insert(0, r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\scripts")
from dex_methods import Dex  # noqa: E402


def main():
    apk = sys.argv[1]
    needle = sys.argv[2]
    lim = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    z = zipfile.ZipFile(apk)
    names = [n for n in z.namelist() if n.endswith(".dex")]
    hits = 0
    for name in names:
        raw = z.read(name)
        try:
            dex = Dex(raw)
        except Exception as exc:                        # noqa: BLE001
            print("skip", name, exc)
            continue
        for i in range(dex.class_defs_size):
            cdo = dex.class_defs_off + i * 32
            try:
                cls, _ = dex.class_data(cdo)
                methods = dex.methods_of(cdo)
            except Exception:                            # noqa: BLE001
                continue
            for _delta, code_off in methods:
                if not code_off:
                    continue
                try:
                    strings = dex.const_strings(code_off)
                except Exception:                        # noqa: BLE001
                    continue
                if any(needle.lower() in s.lower() for s in strings):
                    hits += 1
                    print("\n=== %s  %s  code_off=%d" % (name, cls, code_off))
                    for s in strings:
                        print("   ", s)
                    if hits >= lim:
                        print("\nhit limit reached")
                        return
    print("\ntotal methods matched:", hits)


if __name__ == "__main__":
    main()
