import Foundation
import Combine

@MainActor
final class LXMFManager: ObservableObject {
    static let shared = LXMFManager()

    @Published private(set) var isConnected = false
    @Published private(set) var identityReady = false

    private init() { }

    func start() {
        print("Starting LXMF Manager")
    }

    func stop() {
        print("Stopping LXMF Manager")
    }

    func send(
        text: String,
        to peer: LXMFPeer
    ) {
        guard peer.isDestinationValid else {
            print("Invalid LXMF destination")
            return
        }

        print(
            """
            LXMF SEND
            Peer: \(peer.displayName)
            Destination: \(peer.destinationHash)
            Message: \(text)
            """
        )
    }
}
