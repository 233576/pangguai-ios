import SwiftUI
import UIKit

/// 二维码渲染：用 CoreImage 生成，白底黑码，带一点圆角留白。
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 200

    var body: some View {
        Group {
            if let image = QRCodeView.image(for: text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Flat.surfaceHigh)
                    .overlay(
                        Text("二维码生成失败")
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.textTertiary)
                    )
            }
        }
        .frame(width: size, height: size)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
    }

    static func image(for text: String, scale: CGFloat = 10) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaled = output.transformed(by: transform)
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
