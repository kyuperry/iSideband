import SwiftUI

enum MainAppPage: String, CaseIterable {
    case rnode = "RNode"
    case menu = "Menu"
    case messages = "Messages"

    var icon: String {
        switch self {
        case .rnode:
            return "antenna.radiowaves.left.and.right"

        case .menu:
            return "square.grid.2x2.fill"

        case .messages:
            return "message.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var selectedPage: MainAppPage = .rnode

    var body: some View {
        NavigationStack {
            Group {
                switch selectedPage {
                case .rnode:
                    RNodeHomeView(bluetooth: bluetooth)

                case .menu:
                    MainMenuView(bluetooth: bluetooth)

                case .messages:
                    ConversationsView(bluetooth: bluetooth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                mainPageSelector
            }
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
                            .font(.system(size: 17))

                        Text(page.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(
                        selectedPage == page
                            ? Color.white
                            : Color.primary
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
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
        .frame(maxWidth: 330)
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
    ContentView()
}
