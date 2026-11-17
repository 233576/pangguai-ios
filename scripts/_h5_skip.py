import io, re, os, sys, json

path = os.path.join(os.environ.get('TEMP', '.'), 'recharge_app.js')
text = io.open(path, encoding='utf-8', errors='ignore').read()
print('app.js len', len(text))

# 路由定义
for m in re.finditer(r'path:"([^"]*skip[^"]*)"', text):
    snippet = text[max(0, m.start() - 120):m.start() + 260]
    print('ROUTE', m.group(1))
    print('   ', snippet.replace('\n', ' ')[:360])

# chunk 文件名映射
for m in re.finditer(r'"(skip[^"]*?)":"([0-9a-f]{8})"', text):
    print('CHUNK', m.group(1), m.group(2))

# 首页路由表里 /skip 附近的 chunk 引用
idx = text.find('skip?Company')
print('literal index', idx)
