import io, os, re

t = io.open(os.path.join(os.environ['TEMP'], 'skip.js'), encoding='utf-8', errors='ignore').read()

for m in re.finditer('scanCodeInit', t):
    s = max(0, m.start() - 1400)
    print('=== @%d' % m.start())
    print(t[s:m.start() + 900].replace('\n', ' '))
    print()
