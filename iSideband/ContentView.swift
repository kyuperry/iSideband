import SwiftUI

enum MainAppPage: String, CaseIterable {
    case rnode = "RNode"
    case menu = "Menu"
    case voiceCall = "Call"
    case messages = "Messages"
    case map = "Map"

    var icon: String {
        switch self {
        case .rnode:
            return "antenna.radiowaves.left.and.right"

        case .menu:
            return "square.grid.2x2.fill"

        case .voiceCall:
            return "phone.fill"

        case .messages:
            return "message.fill"

        case .map:
            return "map.fill"
        }
    }
}

private enum AppRoute: Hashable {
    case discoveredPeer(String)
    case message(String)
}

struct ContentView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var notificationRouter =
        NotificationNavigationRouter.shared
    @ObservedObject private var contactStore =
        LXMFContactStore.shared

    @State private var selectedPage: MainAppPage = .rnode
    @State private var navigationPath: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch selectedPage {
                case .rnode:
                    RNodeHomeView(bluetooth: bluetooth)

                case .menu:
                    MainMenuView(bluetooth: bluetooth)

                case .voiceCall:
                    VoiceCallView(bluetooth: bluetooth)

                case .messages:
                    ConversationsView(bluetooth: bluetooth)

                case .map:
                    MeshMapView(bluetooth: bluetooth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                mainPageSelector
            }
            .navigationDestination(for: AppRoute.self) {
                route in
                destination(for: route)
            }
        }
        .task {
            let gpsEnabled = UserDefaults.standard.bool(
                forKey: "gpsInterfaceEnabled"
            )
            let meshLocationEnabled = UserDefaults.standard.bool(
                forKey: TelemetryPreferenceKey.shareLocation
            )
            LocationTelemetryManager.shared.setEnabled(
                gpsEnabled || meshLocationEnabled
            )
            openPendingNotification()
        }
        .onChange(
            of: notificationRouter.pendingRoute
        ) {
            openPendingNotification()
        }
    }

    @ViewBuilder
    private func destination(
        for route: AppRoute
    ) -> some View {
        switch route {
        case .discoveredPeer(let destinationHash):
            DiscoveredPeersView(
                focusedDestinationHash: destinationHash
            )

        case .message(let sourceHash):
            if let contact = contactStore.contact(
                for: sourceHash
            ) {
                MessagesView(
                    bluetooth: bluetooth,
                    contact: contact
                )
            } else {
                DiscoveredPeersView(
                    focusedDestinationHash: sourceHash
                )
            }
        }
    }

    private func openPendingNotification() {
        guard let route =
                notificationRouter.consumePendingRoute() else {
            return
        }

        switch route {
        case .incomingCall:
            selectedPage = .voiceCall
            navigationPath = []

        case .discoveredPeer(let destinationHash):
            selectedPage = .messages
            navigationPath = [
                .discoveredPeer(destinationHash)
            ]

        case .message(let sourceHash):
            selectedPage = .messages
            navigationPath = [
                .message(sourceHash)
            ]
        }
    }

    private var mainPageSelector: some View {
        HStack(spacing: 4) {
            ForEach(MainAppPage.allCases, id: \.self) { page in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPage = page
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: page.icon)
                            .font(.system(size: 16))

                        Text(page.rawValue)
                            .font(.system(size: 10))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(
                        selectedPage == page
                            ? Color.white
                            : Color.primary
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)
                    .background {
                        if selectedPage == page {
                            Capsule()
                                .fill(Color.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(maxWidth: 380)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.18),
            radius: 12,
            y: 6
        )
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

#Preview {
    ContentView(
        bluetooth: BluetoothManager()
    )
}
