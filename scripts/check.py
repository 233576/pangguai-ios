import io
import glob
import yaml

p = yaml.safe_load(io.open('project.yml', encoding='utf-8'))
base = p['settings']['base']
print('project:', p['name'], 'swift', base['SWIFT_VERSION'], 'ios', p['options']['deploymentTarget']['iOS'])
t = p['targets']['Pangguai']
s = dict(base)
s.update(t['settings']['base'])
print('bundle:', s['PRODUCT_BUNDLE_IDENTIFIER'], 'marketing', s['MARKETING_VERSION'], 'build', s['CURRENT_PROJECT_VERSION'])
print('info ver:', t['info']['properties']['CFBundleShortVersionString'], t['info']['properties']['CFBundleVersion'])
print('launchscreen:', repr(t['info']['properties']['UILaunchScreen']))
print('signing allowed:', s['CODE_SIGNING_ALLOWED'], 'family', s['TARGETED_DEVICE_FAMILY'])
print('schemes:', list(p['schemes'].keys()))

w = yaml.safe_load(io.open('.github/workflows/build-unsigned-ipa.yml', encoding='utf-8'))
print('workflow:', w['name'], '| runner', w['jobs']['build']['runs-on'], '| steps', len(w['jobs']['build']['steps']))
print('triggers:', list(w[True] if True in w else w['on']))

total = 0
ok = True
for f in sorted(glob.glob('Sources/**/*.swift', recursive=True)):
    text = io.open(f, encoding='utf-8').read()
    total += text.count('\n')
    # 双引号里的单字符花括号（如 hasPrefix("{")）不算作用域括号
    scoped = text.replace('"{"', '').replace('"}"', '')
    b = (scoped.count('{'), scoped.count('}'))
    pa = (scoped.count('('), scoped.count(')'))
    flag = '' if b[0] == b[1] and pa[0] == pa[1] else '  <== UNBALANCED'
    if flag:
        ok = False
    print('%-46s lines=%4d braces=%d/%d parens=%d/%d%s' % (f, text.count('\n'), b[0], b[1], pa[0], pa[1], flag))
print('swift files balanced:', ok, '| total swift lines:', total)
