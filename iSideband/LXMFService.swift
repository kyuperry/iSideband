import Foundation
import Combine

@MainActor
final class LXMFService: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var statusMessage =
        "LXMF engine not initialized"

    private weak var manager: LXMFManager?
    private weak var bluetooth: BluetoothManager?
    private var isProcessingQueue = false

    func start(
        manager: LXMFManager,
        bluetooth: BluetoothManager
    ) {
        self.manager = manager
        self.bluetooth = bluetooth

        isReady = true
        statusMessage = "LXMF service ready"

        print("LXMF Service started")
    }

    func stop() {
        isReady = false
        isProcessingQueue = false
        statusMessage = "LXMF service stopped"

        print("LXMF Service stopped")
    }

    func processQueue() {
        guard isReady else {
            print("LXMF queue blocked: service is not ready")
            return
        }

        guard !isProcessingQueue else {
            return
        }

        guard let message = manager?.nextQueuedMessage() else {
            return
        }

        isProcessingQueue = true

        Task {
            await simulateTransmission(of: message)

            isProcessingQueue = false
            processQueue()
        }
    }

    private func simulateTransmission(
        of message: LXMFOutgoingMessage
    ) async {
        manager?.updateMessageStatus(
            id: message.id,
            status: .sending
        )

        statusMessage =
            "Sending message to \(message.peer.displayName)"

        try? await Task.sleep(
            for: .seconds(1)
        )

        manager?.updateMessageStatus(
            id: message.id,
            status: .sent
        )

        statusMessage =
            "Message sent to \(message.peer.displayName)"

        print(
            """
            LXMF SIMULATED TRANSMISSION COMPLETE
            Destination: \(message.peer.destinationHash)
            Message: \(message.text)
            """
        )
    }
}
