import SwiftUI
import QuickLook

struct FilePreview: UIViewControllerRepresentable {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        configure(controller)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QLPreviewController,
        context: Context
    ) {
        configure(uiViewController)
    }

    private func configure(_ controller: QLPreviewController) {
        controller.overrideUserInterfaceStyle = isNightVisionEnabled ? .dark : .unspecified
        controller.view.tintColor = isNightVisionEnabled ? .systemRed : nil
        controller.view.backgroundColor = isNightVisionEnabled ? .black : nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
