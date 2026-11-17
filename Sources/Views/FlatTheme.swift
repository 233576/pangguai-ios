import SwiftUI

// MARK: - 色板

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// 扁平风格色板：纯色面、细描边、无毛玻璃、无投影。
enum Flat {
    static let background = Color(hex: 0x0E0F12)
    static let surface = Color(hex: 0x1A1C20)
    static let surfaceHigh = Color(hex: 0x23262B)
    static let surfaceLow = Color(hex: 0x141619)

    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.13)

    static let accent = Color(hex: 0x3B82F6)
    static let green = Color(hex: 0x22C55E)
    static let orange = Color(hex: 0xF59E0B)
    static let red = Color(hex: 0xEF4444)
    static let purple = Color(hex: 0x8B5CF6)
    static let cyan = Color(hex: 0x06B6D4)

    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let fieldRadius: CGFloat = 10

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)
}

// MARK: - 背景

struct FlatBackground: View {
    var body: some View {
        Flat.background.ignoresSafeArea()
    }
}

// MARK: - 卡片

struct FlatCardModifier: ViewModifier {
    var radius: CGFloat = Flat.cardRadius
    var fill: Color = Flat.surface

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Flat.stroke, lineWidth: 1)
                    }
            }
    }
}

extension View {
    /// 扁平卡片：纯色面 + 1px 细描边，无阴影。
    func flatCard(radius: CGFloat = Flat.cardRadius, fill: Color = Flat.surface) -> some View {
        modifier(FlatCardModifier(radius: radius, fill: fill))
    }

    /// 内凹的输入框/内容块。
    func flatField(radius: CGFloat = Flat.fieldRadius,
                   fill: Color = Flat.surfaceLow) -> some View {
        modifier(FlatFieldModifier(radius: radius, fill: fill))
    }
}

struct FlatFieldModifier: ViewModifier {
    var radius: CGFloat = Flat.fieldRadius
    var fill: Color = Flat.surfaceLow

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Flat.stroke, lineWidth: 1)
                    }
            }
    }
}

// MARK: - 按钮

/// 扁平按钮：`filled` 为实心主按钮（强调色底、白字），否则为次级按钮（面色 + 描边）。
struct FlatButtonStyle: ButtonStyle {
    var tint: Color = Flat.accent
    var filled: Bool = false
    var radius: CGFloat = Flat.controlRadius
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(filled ? Color.white : Flat.textPrimary)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(filled ? tint : Flat.surfaceHigh)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(filled ? Color.clear : Flat.strokeStrong, lineWidth: 1)
                    }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 胶囊 chip

struct FlatPill: ViewModifier {
    var selected: Bool = false
    var tint: Color = Flat.accent

    func body(content: Content) -> some View {
        content
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? tint.opacity(0.18) : Flat.surfaceHigh)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(selected ? tint.opacity(0.55) : Flat.strokeStrong,
                                          lineWidth: 1)
                    }
            }
    }
}

extension View {
    func flatPill(selected: Bool = false, tint: Color = Flat.accent) -> some View {
        modifier(FlatPill(selected: selected, tint: tint))
    }
}

// MARK: - 状态标识

/// 扁平状态块：纯色圆底 + 图标，颜色表达状态。
struct FlatStatusMark: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// 细进度条（扁平版：纯色轨道 + 纯色填充）。
struct FlatProgressBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 分区标题

struct FlatSectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Flat.textSecondary)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

// MARK: - 分隔线

struct FlatDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Flat.stroke)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}
