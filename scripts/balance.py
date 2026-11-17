"""更精确的 Swift 括号检查：正确跳过字符串字面量与转义（含 \\( 插值）。"""
import io
import sys


def scan(path):
    text = io.open(path, encoding='utf-8').read()
    braces = 0
    parens = 0
    brackets = 0
    i = 0
    n = len(text)
    in_str = False
    in_line_comment = False
    in_block = 0
    while i < n:
        ch = text[i]
        if in_line_comment:
            if ch == '\n':
                in_line_comment = False
            i += 1
            continue
        if in_block:
            if ch == '/' and i + 1 < n and text[i + 1] == '*':
                in_block += 1
                i += 2
                continue
            if ch == '*' and i + 1 < n and text[i + 1] == '/':
                in_block -= 1
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
            in_line_comment = True
            i += 2
            continue
        if ch == '/' and i + 1 < n and text[i + 1] == '*':
            in_block = 1
            i += 2
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == '{':
            braces += 1
        elif ch == '}':
            braces -= 1
        elif ch == '(':
            parens += 1
        elif ch == ')':
            parens -= 1
        elif ch == '[':
            brackets += 1
        elif ch == ']':
            brackets -= 1
        i += 1
    return braces, parens, brackets, text.count('\n') + 1


if __name__ == '__main__':
    paths = sys.argv[1:]
    bad = False
    for p in paths:
        b, pa, br, lines = scan(p)
        flag = '' if b == 0 and pa == 0 and br == 0 else '  <== UNBALANCED'
        if flag:
            bad = True
        print('%-52s {}=%+d () =%+d []=%+d lines=%d%s' % (p.split('Sources')[-1], b, pa, br, lines, flag))
    print('OK' if not bad else 'FAIL')
