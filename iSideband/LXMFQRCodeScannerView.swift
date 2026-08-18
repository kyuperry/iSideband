import AVFoundation
import SwiftUI

enum LXMFQRCodeScannerError: LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "The camera is unavailable on this device."
        case .permissionDenied:
            return "Camera access is required to scan QR codes. Enable it in Settings."
        case .invalidCode:
            return "That QR code is not an LXMF paper message."
        }
    }
}

struct LXMFQRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let completion: (Result<String, Error>) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LXMFQRCodeCameraView(completion: completion)
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white, lineWidth: 3)
                    .frame(width: 270, height: 270)
                    .shadow(color: .black.opacity(0.5), radius: 4)

                VStack {
                    Spacer()
                    Text("Place an LXMF message or peer QR code inside the frame")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(.bottom, 48)
                }
                .padding(.horizontal)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct LXMFQRCodeCameraView: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.completion = completion
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QRScannerViewController,
        context: Context
    ) {}
}

private final class QRScannerViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate {
    var completion: ((Result<String, Error>) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "com.kyleperry.iSideband.qr-scanner"
    )
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didComplete = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted
                        ? self?.configureSession()
                        : self?.finish(.failure(LXMFQRCodeScannerError.permissionDenied))
                }
            }
        default:
            finish(.failure(LXMFQRCodeScannerError.permissionDenied))
        }
    }

    private func configureSession() {
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ), let input = try? AVCaptureDeviceInput(device: camera),
        session.canAddInput(input) else {
            finish(.failure(LXMFQRCodeScannerError.cameraUnavailable))
            return
        }

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            finish(.failure(LXMFQRCodeScannerError.cameraUnavailable))
            return
        }

        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        sessionQueue.async { [session] in session.startRunning() }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        finish(.success(value))
    }

    private func finish(_ result: Result<String, Error>) {
        guard !didComplete else { return }
        didComplete = true
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        completion?(result)
    }
}
