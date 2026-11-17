import io, os, re

t = io.open(os.path.join(os.environ['TEMP'], 'skip.js'), encoding='utf-8', errors='ignore').read()
print('len', len(t))

def show(pat, span=260, limit=8):
    print('=== ', pat)
    for m in list(re.finditer(pat, t))[:limit]:
        print('  @%d  %s' % (m.start(), t[max(0, m.start() - span // 2):m.start() + span].replace('\n', ' ')))

show('NQT')
show('CommunicateType')
show('scan/v2')
show('goods/normal/details')
show('findByCode|findGoods|goodsId')
show('weixin|wx\\.|miniprogram|navigateToMiniProgram')
show('deviceCode|machineCode')
