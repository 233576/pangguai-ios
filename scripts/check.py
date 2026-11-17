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


def count_brackets(text):
    """数括号，跳过字符串字面量、行注释与块注释。

    旧实现是先「把字符串内容抹掉再计数」，遇到三引号多行串或插值写法就会
    把状态翻转错，导致误报（AppStore 曾报 parens 318/321 其实完全平衡）。
    """
    counters = {'{': 0, '}': 0, '(': 0, ')': 0}
    i = 0
    n = len(text)
    in_str = False
    in_line = False
    block = 0
    while i < n:
        ch = text[i]
        if in_line:
            if ch == '\n':
                in_line = False
            i += 1
            continue
        if block:
            if ch == '/' and i + 1 < n and text[i + 1] == '*':
                block += 1
                i += 2
                continue
            if ch == '*' and i + 1 < n and text[i + 1] == '/':
                block -= 1
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if ch == '\\':
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '/' and i + 1 < n and text[i + 1] == '/':
            in_line = True
            i += 2
            continue
        if ch == '/' and i + 1 < n and text[i + 1] == '*':
            block = 1
            i += 2
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch in counters:
            counters[ch] += 1
        i += 1
    return counters


total = 0
ok = True
for f in sorted(glob.glob('Sources/**/*.swift', recursive=True)):
    text = io.open(f, encoding='utf-8').read()
    total += text.count('\n')
    counters = count_brackets(text)
    b = (counters['{'], counters['}'])
    pa = (counters['('], counters[')'])
    flag = '' if b[0] == b[1] and pa[0] == pa[1] else '  <== UNBALANCED'
    if flag:
        ok = False
    print('%-46s lines=%4d braces=%d/%d parens=%d/%d%s' % (f, text.count('\n'), b[0], b[1], pa[0], pa[1], flag))
print('swift files balanced:', ok, '| total swift lines:', total)
