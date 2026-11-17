import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\scripts\check.py'
t = io.open(p, encoding='utf-8').read()

start = t.index('def strip_strings(text):')
end = t.index('total = 0')

new_func = '''def count_brackets(text):
    """数括号，跳过字符串字面量、行注释与块注释。

    旧实现是先「把字符串内容抹掉再计数」，遇到 `"""` 多行串或 `\\\\(` 插值就会
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
            if ch == '\\n':
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
            if ch == '\\\\':
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


'''

t = t[:start] + new_func + t[end:]

old_loop = '''    code = strip_strings(text)
    b = (code.count('{'), code.count('}'))
    pa = (code.count('('), code.count(')'))'''
new_loop = '''    counters = count_brackets(text)
    b = (counters['{'], counters['}'])
    pa = (counters['('], counters[')'])'''
assert old_loop in t
t = t.replace(old_loop, new_loop, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('check.py patched')
