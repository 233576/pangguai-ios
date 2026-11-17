import SwiftUI

/// 短信验证码登录。胖乖用 /user/reg 同时完成注册与登录。
struct LoginSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var code = ""
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
                        Text("只做洗衣机。用手机号收验证码即可，不需要另装 App。")
                            .font(.system(size: 13))
                            .foregroundStyle(Flat.textSecondary)
                    }
                    .padding(.top, 16)

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

                    Button {
                        Task {
                            loggingIn = true
                            let ok = await store.login(phone: phone, code: code)
                            loggingIn = false
                            if ok { dismiss() }
                        }
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

                    Text("同校同学用过的机器会自动记在首页「最近」，下次点一下就直接下单。")
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
}
