import Combine
import Foundation

enum NotificationRoute: Equatable {
    case discoveredPeer(destinationHash: String)
    case message(sourceHash: String)
}

@MainActor
final class NotificationNavigationRouter: ObservableObject {
    static let shared = NotificationNavigationRouter()

    @Published private(set) var pendingRoute:
        NotificationRoute?

    private init() {}

    func receive(userInfo: [AnyHashable: Any]) {
        if let sourceHash =
                userInfo["sourceHash"] as? String {
            pendingRoute = .message(
                sourceHash: sourceHash
            )
            return
        }

        if let destinationHash =
                userInfo["destinationHash"] as? String {
            pendingRoute = .discoveredPeer(
                destinationHash: destinationHash
            )
        }
    }

    func consumePendingRoute() -> NotificationRoute? {
        defer {
            pendingRoute = nil
        }

        return pendingRoute
    }
}
