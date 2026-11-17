import io

base = r'C:\Users\Chen\Documents\deepseek-harness\default-workspace\pangguai-ios\Sources'

# ---------- 1) Models.swift：PGOrder 加倒计时计算 ----------
p = base + r'\Core\Models.swift'
t = io.open(p, encoding='utf-8').read()

anchor = '''    var title: String {
        if !machineName.isEmpty { return machineName }
        if !functionName.isEmpty { return functionName }
        return "洗衣机订单"
    }
}'''

add = '''    var title: String {
        if !machineName.isEmpty { return machineName }
        if !functionName.isEmpty { return functionName }
        return "洗衣机订单"
    }

    // MARK: - 洗涤进度

    /// `createTime` 是下单时间，形如 `2026-11-17 13:56:08`。
    var startedAt: Date? {
        PGOrder.timeFormatter.date(from: createTime)
            ?? PGOrder.timeFormatterAlt.date(from: createTime)
    }

    /// 预计结束时间 = 下单时间 + 套餐时长。
    var endsAt: Date? {
        guard let start = startedAt, minutes > 0 else { return nil }
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 只有「已支付 / 进行中」且还没到点，才算正在洗。
    func isRunning(now: Date = Date()) -> Bool {
        guard status == 1 || status == 2, let end = endsAt else { return false }
        return end > now
    }

    func remaining(now: Date = Date()) -> TimeInterval {
        guard let end = endsAt else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// 0…1，用于进度条。
    func progress(now: Date = Date()) -> Double {
        guard let start = startedAt, let end = endsAt, end > start else { return 0 }
        let total = end.timeIntervalSince(start)
        let done = now.timeIntervalSince(start)
        return min(1, max(0, done / total))
    }

    /// `24:13` / `1:02:30`。
    func remainingText(now: Date = Date()) -> String {
        let seconds = Int(remaining(now: now).rounded())
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// `13:42 洗好` 这类文案。
    func finishText(now: Date = Date()) -> String {
        guard let end = endsAt else { return "—" }
        if end <= now { return "已洗好" }
        return PGOrder.clockFormatter.string(from: end) + " 洗好"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let timeFormatterAlt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}'''

assert anchor in t
t = t.replace(anchor, add, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('Models patched')

# ---------- 2) AppStore.swift：秒级时钟 ----------
p = base + r'\Core\AppStore.swift'
t = io.open(p, encoding='utf-8').read()

old = '''    @Published private(set) var codeCountdown = 0
    @Published private(set) var lastQueryCode = ""

    private var client = PGClient()
    private var countdownTask: Task<Void, Never>?'''
new = '''    @Published private(set) var codeCountdown = 0
    @Published private(set) var lastQueryCode = ""

    /// 每秒跳动一次，驱动洗涤倒计时。只有界面里真的显示倒计时时才跑，省电。
    @Published private(set) var now = Date()
    private var clock: Timer?
    private var finishedOrderIds: Set<String> = []

    private var client = PGClient()
    private var countdownTask: Task<Void, Never>?'''
assert old in t
t = t.replace(old, new, 1)

# 在 "// MARK: - 工具" 之前插入时钟与进度 API
anchor2 = '''    // MARK: - 工具'''
add2 = '''    // MARK: - 洗涤进度

    /// 当前正在洗的订单（服务端 status 1/2 且未到预计结束时间）。
    var runningOrder: PGOrder? {
        orders.first { $0.isRunning(now: now) }
    }

    /// 最近一笔已支付/进行中的订单，倒计时结束后用来显示「洗好了」。
    var latestPaidOrder: PGOrder? {
        orders.first { $0.status == 1 || $0.status == 2 }
    }

    func startClock() {
        guard clock == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.checkFinish()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    /// 倒计时走完的那一下：震动 + 记一条日志，只触发一次。
    private func checkFinish() {
        for order in orders where order.status == 1 || order.status == 2 {
            guard let end = order.endsAt, end <= now else { continue }
            let key = order.id.isEmpty ? order.orderNo : order.id
            guard !finishedOrderIds.contains(key) else { continue }
            finishedOrderIds.insert(key)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            log("洗涤完成：\\(order.title)  \\(order.functionName)")
        }
    }

    // MARK: - 工具'''
assert anchor2 in t
t = t.replace(anchor2, add2, 1)

if 'import UIKit' not in t:
    t = t.replace('import Foundation', 'import Foundation\nimport UIKit', 1)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('AppStore patched')
