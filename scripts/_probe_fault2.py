"""把 dex 里跟「设备状态/异常」相关的中文文案全捞出来，并在附近找字段名。"""
import re
import zipfile

APK = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pg\inbox\com.qiekj.user.apk'

CJK_RUN = re.compile(r'(?:[\u4e00-\u9fff\uff0c\u3002\uff01\uff1f\uff1a\u3001]|[\x20-\x7e]){4,}')
CJK_ONLY = re.compile(r'[\u4e00-\u9fff]{2,}')
ASCII_ID = re.compile(r'[A-Za-z_][A-Za-z0-9_]{2,}')

KEY = ['设备', '异常', '暂停', '门', '故障', '离线', '关机', '报修', '维修', '仓门', '桶']

FIELDS = ['deviceStatus', 'workStatus', 'goodsStatus', 'errorCode', 'errorMsg',
          'faultCode', 'faultMsg', 'pauseReason', 'stopReason', 'deviceMsg',
          'statusMsg', 'runStatus', 'machineStatus', 'exceptionMsg', 'deviceState',
          'goodsState', 'statusDesc', 'workStatusDesc', 'deviceErrorCode', 'errMsg']


def main():
    z = zipfile.ZipFile(APK)
    for name in [n for n in z.namelist() if n.endswith('.dex')]:
        blob = z.read(name)
        text = blob.decode('utf-8', 'ignore')

        found = set()
        for m in CJK_ONLY.finditer(text):
            s = m.group()
            if any(k in s for k in KEY) and len(s) <= 40:
                found.add(s)
        if not found:
            continue
        print('\n===== %s 中文候选（%d）=====' % (name, len(found)))
        for s in sorted(found, key=len, reverse=True)[:60]:
            print('   ', s)

        fhits = [f for f in FIELDS if f.encode('ascii') in blob]
        if fhits:
            print('   字段命中:', ' '.join(fhits))


if __name__ == '__main__':
    main()
