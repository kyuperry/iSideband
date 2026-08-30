import Combine
import Foundation

enum NotificationRoute: Equatable, Sendable {
    case discoveredPeer(destinationHash: String)
    case message(sourceHash: String)
    case incomingCall(callerHash: String)
}

@MainActor
final class NotificationNavigationRouter: ObservableObject {
    static let shared = NotificationNavigationRouter()

    @Published private(set) var pendingRoute:
        NotificationRoute?

    private init() {}

    func receive(route: NotificationRoute) {
        pendingRoute = route
    }

    func receive(userInfo: [AnyHashable: Any]) {
        if userInfo["incomingCall"] as? Bool == true {
            pendingRoute = .incomingCall(
                callerHash: userInfo["callerHash"] as? String ?? ""
            )
            return
        }

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
