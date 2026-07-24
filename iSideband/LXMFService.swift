import Foundation
import Combine

@MainActor
final class LXMFService: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var statusMessage = "LXMF engine not initialized"

    func start() {
        isReady = false
        statusMessage = "Reticulum/LXMF implementation pending"
    }

    func send(
        text: String,
        destination: String
    ) {
        guard isReady else {
            print(
                "LXMF send blocked: engine is not initialized"
            )
            return
        }

        print(
            "LXMF message queued for \(destination): \(text)"
        )
    }
}
