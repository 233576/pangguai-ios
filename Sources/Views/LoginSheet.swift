import SwiftUI
import UIKit

/// 登录。两条路：
/// ① 手机号 + 短信验证码（`/user/reg` 同时完成注册与登录）
/// ② 直接粘贴 token —— 胖乖小程序和 App 共用同一套凭证，
///    在电脑端 Reqable／手机端抓包里看到 `token=xxxx` 就能直接用，省掉验证码。
struct LoginSheet: View {
    /// 登录成功后回调（用于接着把已输入的机器码查出来）。
    var onSuccess: (() -> Void)?

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0
    @State private var phone = ""
    @State private var code = ""
    @State private var tokenText = ""
    @State private var sending = false
    @State private var loggingIn = false

    var body: some View {
        ZStack {
            FlatBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登录胖乖生活")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Flat.textPrimary)
                        Text("只做洗衣机。手机号收验证码，或者直接粘贴一个有效 token。")
                            .font(.system(size: 13))
                            .foregroundStyle(Flat.textSecondary)
                    }
                    .padding(.top, 16)

                    HStack(spacing: 8) {
                        modeChip("手机号登录", index: 0)
                        modeChip("粘贴凭证", index: 1)
                        Spacer()
                    }

                    if mode == 0 {
                        smsCard
                    } else {
                        tokenCard
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if loggingIn {
                                ProgressView().tint(.white)
                            }
                            Text(loggingIn ? "登录中…" : "登录")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 50))
                    .disabled(loggingIn)

                    Text(mode == 0
                         ? "同校同学用过的机器会自动记在首页「最近」，下次点一下就直接下单。"
                         : "凭证一般 30 天有效。抓包位置：小程序里点任意请求，看表单字段 `token=`。")
                        .font(.system(size: 12))
                        .foregroundStyle(Flat.textTertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if phone.isEmpty { phone = store.settings.lastPhone }
        }
    }

    // MARK: - 组件

    private func modeChip(_ title: String, index: Int) -> some View {
        Button {
            mode = index
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == index ? Flat.accent : Flat.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .flatPill(selected: mode == index, tint: Flat.accent)
        }
        .buttonStyle(.plain)
    }

    private var smsCard: some View {
        VStack(spacing: 12) {
            TextField("手机号", text: $phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .flatField()

            HStack(spacing: 10) {
                TextField("验证码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .flatField()

                Button {
                    Task {
                        sending = true
                        _ = await store.sendCode(phone: phone)
                        sending = false
                    }
                } label: {
                    Text(store.codeCountdown > 0 ? "\(store.codeCountdown)s" : "发送")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 74)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 46))
                .disabled(sending || store.codeCountdown > 0)
            }
        }
        .padding(16)
        .flatCard()
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("粘贴 token", text: $tokenText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .flatField()

            HStack(spacing: 10) {
                Button {
                    if let text = UIPasteboard.general.string {
                        tokenText = text
                    }
                } label: {
                    Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 42))

                Button {
                    tokenText = ""
                } label: {
                    Text("清空")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 62)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.textSecondary, filled: false, height: 42))
            }

            Text("粘 `token=4813f4…` 这种整段也行，会自动截取。")
                .font(.system(size: 11))
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 提交

    private func submit() async {
        loggingIn = true
        defer { loggingIn = false }
        if mode == 0 {
            let ok = await store.login(phone: phone, code: code)
            if ok {
                dismiss()
                onSuccess?()
            }
        } else {
            await store.login(withToken: tokenText)
            if store.loggedIn, store.user != nil {
                dismiss()
                onSuccess?()
            }
        }
    }
}
