"""在胖乖 APK 的 dex 里找订单状态相关的字符串与字段名。

两种搜法：
1) ASCII（字段名、状态常量名）
2) UTF-8 中文（"待支付"/"进行中"/"已完成"/"已取消" 这些文案，看服务端/客户端用哪个词）

字符串池里相邻的条目经常是同一声明顺序，所以命中点前后各打印若干串便于比对。
"""
import io
import re
import sys
import zipfile

APK = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pg\inbox\com.qiekj.user.apk'

ASCII = re.compile(rb'[\x20-\x7e]{3,}')
CJK = re.compile('[\u4e00-\u9fff]{2,}')

PROBE = ['已完成', '已取消', '进行中', '待支付', '待使用', '已退款', '退款中',
         '待启动', '使用中', '订单状态', '取消']
FIELDS = ['orderStatus', 'orderStatusName', 'statusName', 'payStatus', 'cancelTime',
          'payTime', 'completeTime', 'finishTime', 'createTime', 'markMinutes',
          'machineFunctionName', 'orderStatusStr']


def strings(blob):
    out = []
    for m in ASCII.finditer(blob):
        out.append(m.group().decode('ascii', 'ignore'))
    return out


def utf8_strings(blob):
    text = blob.decode('utf-8', 'ignore')
    return text


def main():
    z = zipfile.ZipFile(APK)
    dexes = [n for n in z.namelist() if n.endswith('.dex')]
    print('dex:', dexes)

    for name in dexes:
        blob = z.read(name)
        hits = []
        for word in PROBE:
            if word.encode('utf-8') in blob:
                hits.append(word)
        fhits = [f for f in FIELDS if f.encode('ascii') in blob]
        if hits or fhits:
            print('\n== %s ==' % name)
            if hits:
                print('  中文命中:', ' '.join(hits))
            if fhits:
                print('  字段命中:', ' '.join(fhits))

    # 找 orderStatus 附近的字符串，帮助判断状态码顺序
    print('\n---- orderStatus 上下文 ----')
    for name in dexes:
        blob = z.read(name)
        idx = 0
        count = 0
        while True:
            idx = blob.find(b'orderStatus', idx)
            if idx < 0 or count >= 6:
                break
            lo = max(0, idx - 400)
            hi = min(len(blob), idx + 400)
            seg = blob[lo:hi].decode('utf-8', 'ignore')
            seg = ''.join(ch if 32 <= ord(ch) < 127 or '\u4e00' <= ch <= '\u9fff' else '|' for ch in seg)
            print('[%s @%d] %s' % (name, idx, seg))
            idx += 1
            count += 1


if __name__ == '__main__':
    main()
