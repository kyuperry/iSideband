import Combine
import SwiftUI

@MainActor
final class VoiceCallManager: ObservableObject {
    enum State: Equatable {
        case idle
        case calling(LXMFPeer)
        case incoming(LXMFPeer)
        case active(LXMFPeer)

        var peer: LXMFPeer? {
            switch self {
            case .idle: nil
            case .calling(let peer), .incoming(let peer), .active(let peer): peer
            }
        }
    }

    static let shared = VoiceCallManager()
    @Published private(set) var state: State = .idle
    @Published private(set) var statusMessage = "Ready"

    private let prefix = "[iSideband Voice Call v1]"
    private var handledMessages = Set<String>()

    private init() {}

    func call(_ peer: LXMFPeer) {
        switch state {
        case .incoming(let incomingPeer)
            where incomingPeer.destinationHash == peer.destinationHash:
            send("ACCEPT", to: incomingPeer)
            state = .active(incomingPeer)
            statusMessage = "Connected to \(incomingPeer.displayName)"
        case .idle:
            guard send("REQUEST", to: peer) else { return }
            state = .calling(peer)
            statusMessage = "Calling \(peer.displayName)…"
        default:
            statusMessage = "End the current call before starting another."
        }
    }

    func reject() {
        guard case .incoming(let peer) = state else {
            statusMessage = "There is no incoming call to reject."
            return
        }
        _ = send("REJECT", to: peer)
        state = .idle
        statusMessage = "Call rejected"
    }

    func end() {
        guard let peer = state.peer else {
            statusMessage = "There is no call to end."
            return
        }
        guard !isIncoming else {
            statusMessage = "Use Reject to decline the incoming call."
            return
        }
        _ = send("END", to: peer)
        state = .idle
        statusMessage = "Call ended"
    }

    func sendVoiceSegment(at url: URL) {
        guard case .active(let peer) = state else {
            statusMessage = "Accept or establish a call first."
            return
        }
        guard LXMFManager.shared.sendAttachment(
            at: url,
            name: url.lastPathComponent,
            mimeType: "audio/ogg",
            type: .voiceNote,
            caption: "Voice call",
            to: peer
        ) != nil else {
            statusMessage = "Voice segment could not be queued."
            return
        }
        statusMessage = "Voice segment queued"
    }

    func processIncoming(peers: [LXMFPeer]) {
        for peer in peers {
            for message in LXMFIncomingMessageStore.shared.messages(
                for: peer.destinationHash
            ) where !message.isOutgoing && message.text.hasPrefix(prefix) {
                let identifier = message.lxmfHash ?? message.id.uuidString
                guard handledMessages.insert(identifier).inserted else { continue }
                let command = message.text
                    .dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                handle(command, from: peer)
            }
        }
    }

    private var isIncoming: Bool {
        if case .incoming = state { return true }
        return false
    }

    private func handle(_ command: String, from peer: LXMFPeer) {
        switch command {
        case "REQUEST":
            guard case .idle = state else {
                _ = send("REJECT", to: peer)
                return
            }
            state = .incoming(peer)
            statusMessage = "Incoming call from \(peer.displayName)"
        case "ACCEPT":
            guard case .calling(let calledPeer) = state,
                  calledPeer.destinationHash == peer.destinationHash else { return }
            state = .active(peer)
            statusMessage = "Connected to \(peer.displayName)"
        case "REJECT":
            guard state.peer?.destinationHash == peer.destinationHash else { return }
            state = .idle
            statusMessage = "\(peer.displayName) rejected the call"
        case "END":
            guard state.peer?.destinationHash == peer.destinationHash else { return }
            state = .idle
            statusMessage = "Call ended by \(peer.displayName)"
        default:
            break
        }
    }

    @discardableResult
    private func send(_ command: String, to peer: LXMFPeer) -> Bool {
        guard LXMFManager.shared.send(
            text: "\(prefix) \(command)",
            to: peer
        ) != nil else {
            statusMessage = "The call signal could not be queued. Check the selected interface."
            return false
        }
        return true
    }
}

struct VoiceCallView: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var peerStore = ReticulumDiscoveredPeerStore.shared
    @ObservedObject private var contactStore = LXMFContactStore.shared
    @ObservedObject private var incomingStore = LXMFIncomingMessageStore.shared
    @StateObject private var callManager = VoiceCallManager.shared

    @State private var identityHash = ""
    @State private var showingVoiceRecorder = false
    @State private var validationMessage: String?

    private var peers: [LXMFPeer] {
        var seen = Set<String>()
        return peerStore.peers.compactMap { discovered in
            guard seen.insert(discovered.destinationHash).inserted else { return nil }
            let contactName = contactStore.contact(for: discovered.destinationHash)?.displayName
            return LXMFPeer(
                displayName: contactName ?? discovered.displayName ?? "Unknown Node",
                destinationHash: discovered.destinationHash
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voice Call")
                    .font(.largeTitle.bold())
                Text("Half-duplex Opus voice over the selected Reticulum interface")
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
            }

            HStack(spacing: 0) {
                TextField(
                    "Identity Hash or select Discovered Peer",
                    text: $identityHash
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(minHeight: 46)

                Divider().frame(height: 28)

                Menu {
                    if peers.isEmpty {
                        Text("No discovered peers")
                    } else {
                        ForEach(peers) { peer in
                            Button {
                                identityHash = peer.destinationHash
                                validationMessage = nil
                            } label: {
                                Text("\(peer.displayName) — \(shortHash(peer.destinationHash))")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 46)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Select discovered peer")
            }
            .background(fieldColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.primary.opacity(0.18), lineWidth: 1)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(isNightVisionEnabled ? NightVisionPalette.secondary : .red)
            }

            callStatus

            if case .active = callManager.state {
                Button {
                    showingVoiceRecorder = true
                } label: {
                    Label("Push to Talk", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .nightVisionProminentButton()
            }

            Spacer()

            HStack(spacing: 14) {
                Button("End") {
                    callManager.end()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)

                Button("Reject") {
                    callManager.reject()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)

                Button("Call") {
                    startOrAcceptCall()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .onAppear {
            adoptCurrentPeer()
            callManager.processIncoming(peers: peers)
        }
        .onChange(of: incomingStore.revision) { _, _ in
            callManager.processIncoming(peers: peers)
            adoptCurrentPeer()
        }
        .onChange(of: callManager.state) { _, _ in
            adoptCurrentPeer()
        }
        .sheet(isPresented: $showingVoiceRecorder) {
            VoiceNoteRecorderView(isPushToTalk: true) { url in
                callManager.sendVoiceSegment(at: url)
            }
        }
    }

    private var callStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(callManager.statusMessage)
                    .font(.headline)
                if let peer = callManager.state.peer {
                    Text(peer.destinationHash)
                        .font(.caption.monospaced())
                        .foregroundStyle(secondaryColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 14))
    }

    private func startOrAcceptCall() {
        let cleaned = identityHash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let name = contactStore.contact(for: cleaned)?.displayName
            ?? peerStore.peers.first(where: { $0.destinationHash == cleaned })?.displayName
            ?? "Unknown Node"
        let peer = LXMFPeer(displayName: name, destinationHash: cleaned)
        guard peer.isDestinationValid else {
            validationMessage = "Enter a valid 32-character hexadecimal Identity Hash."
            return
        }
        validationMessage = nil
        callManager.call(peer)
    }

    private func adoptCurrentPeer() {
        if let hash = callManager.state.peer?.destinationHash {
            identityHash = hash
        }
    }

    private func shortHash(_ hash: String) -> String {
        guard hash.count > 12 else { return hash }
        return "\(hash.prefix(6))…\(hash.suffix(6))"
    }

    private var statusIcon: String {
        switch callManager.state {
        case .idle: "phone"
        case .calling: "phone.arrow.up.right"
        case .incoming: "phone.arrow.down.left"
        case .active: "waveform"
        }
    }

    private var fieldColor: Color {
        isNightVisionEnabled ? NightVisionPalette.field : Color.secondary.opacity(0.10)
    }

    private var secondaryColor: Color {
        isNightVisionEnabled ? NightVisionPalette.secondary : Color.secondary
    }
}

#Preview {
    VoiceCallView(bluetooth: BluetoothManager())
        .environmentObject(LXMFManager.shared)
}
