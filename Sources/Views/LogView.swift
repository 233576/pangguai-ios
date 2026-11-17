import SwiftUI
import UIKit

/// 日志页：请求与响应原文，方便排查。
struct LogView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            FlatBackground()

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("日志")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Flat.textPrimary)
                        Text("\(store.logs.count) 行")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.textTertiary)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = store.logs.joined(separator: "\n")
                        store.noticeMessage = "日志已复制"
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Flat.accent)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Flat.surfaceHigh)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Flat.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Flat.surfaceHigh)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if store.logs.isEmpty {
                            Text("还没有日志。点「查询这台洗衣机」之后，这里会记录每一步请求。")
                                .font(.system(size: 12))
                                .foregroundStyle(Flat.textTertiary)
                                .padding(.top, 12)
                        } else {
                            ForEach(store.logs.indices, id: \.self) { index in
                                Text(store.logs[index])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Flat.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .flatCard(fill: Flat.surfaceLow)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 104)
        }
    }
}
