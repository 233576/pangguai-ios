import AVFoundation
import SwiftUI
import UIKit

/// 扫码取机器码：支付宝/微信扫到的是 `NQT=...` 链接或纯码，都会交给 onCode。
struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onCode: (String) -> Void

    @StateObject private var scanner = ScannerEngine()
    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var manual = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if permission == .authorized {
                    ScannerPreview(engine: scanner)
                        .ignoresSafeArea()
                    reticle
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Flat.textSecondary)
                        Text(permission == .denied ? "相机权限被关掉了" : "需要相机权限才能扫码")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Flat.textPrimary)
                        Text(permission == .denied
                             ? "到「设置 → 隐私与安全性 → 相机」里打开，或者直接在下方手动输入机器码。"
                             : "也可以直接在下方手动输入机器码。")
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Flat.textTertiary)
                            .padding(.horizontal, 24)
                        if permission == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                            Button("去设置") { UIApplication.shared.open(url) }
                                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 44))
                                .padding(.horizontal, 60)
                        }
                    }
                }

                VStack {
                    Spacer()
                    manualInput
                }
            }
            .navigationTitle("扫码 / 机器码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Flat.accent)
                }
            }
        }
        .onAppear {
            scanner.onCode = { code in
                onCode(code)
                dismiss()
            }
            requestPermission()
        }
        .onDisappear {
            scanner.stop()
        }
    }

    private var reticle: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 220, height: 220)
            Text("对准洗衣机上的二维码")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var manualInput: some View {
        VStack(spacing: 10) {
            TextField("手动输入机器码（如 NQT…）", text: $manual)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .flatField()
            Button {
                let code = manual.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { return }
                onCode(code)
                dismiss()
            } label: {
                Text("用这个机器码")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 48))
        }
        .padding(16)
        .background(Flat.surface.opacity(0.96))
    }

    private func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
            scanner.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    permission = granted ? .authorized : .denied
                    if granted { scanner.start() }
                }
            }
        default:
            permission = .denied
        }
    }
}

/// 相机预览层。
private struct ScannerPreview: UIViewRepresentable {
    let engine: ScannerEngine

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.attach(engine.session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }

        func attach(_ session: AVCaptureSession) {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)
            previewLayer = layer
        }
    }
}

/// 管理 AVCaptureSession，识别到二维码就回调一次。
final class ScannerEngine: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private var configured = false
    private var handled = false
    private let queue = DispatchQueue(label: "pangguai.scanner")

    func start() {
        guard configureIfNeeded() else { return }
        handled = false
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr, .code128, .ean13]
        session.commitConfiguration()
        configured = true
        return true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue, !value.isEmpty else { continue }
            handled = true
            stop()
            onCode?(value)
            return
        }
    }
}
