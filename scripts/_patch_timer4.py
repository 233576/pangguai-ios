import io

p = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources\Views\AppShell.swift'
t = io.open(p, encoding='utf-8').read()

old = '''        .preferredColorScheme(.dark)
        .task {
            await store.autoDetectOnLaunch()
        }'''
new = '''        .preferredColorScheme(.dark)
        .task {
            await store.autoDetectOnLaunch()
        }
        .onAppear {
            // 洗涤倒计时：每秒重算剩余时间，退到后台就停，回到前台接着走。
            store.startClock()
        }
        .onDisappear {
            store.stopClock()
        }'''
assert old in t
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('AppShell patched')
