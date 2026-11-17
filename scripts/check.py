import glob
import io

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


def strip_strings(text):
    """把 Swift 字符串字面量内容抹掉，避免 JSON 里的引号/花括号干扰计数。"""
    out = []
    in_string = False
    escaped = False
    for ch in text:
        if in_string:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == '"':
                in_string = False
                out.append('"')
            continue
        if ch == '"':
            in_string = True
            out.append('"')
            continue
        out.append(ch)
    return ''.join(out)


total = 0
ok = True
for f in sorted(glob.glob('Sources/**/*.swift', recursive=True)):
    text = io.open(f, encoding='utf-8').read()
    total += text.count('\n')
    code = strip_strings(text)
    b = (code.count('{'), code.count('}'))
    pa = (code.count('('), code.count(')'))
    flag = '' if b[0] == b[1] and pa[0] == pa[1] else '  <== UNBALANCED'
    if flag:
        ok = False
    print('%-46s lines=%4d braces=%d/%d parens=%d/%d%s' % (f, text.count('\n'), b[0], b[1], pa[0], pa[1], flag))
print('swift files balanced:', ok, '| total swift lines:', total)
