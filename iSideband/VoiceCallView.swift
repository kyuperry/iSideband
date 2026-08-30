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

    private let bridge = ReticulumCoreBridge.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        bridge.$lxstCallStatus
            .combineLatest(bridge.$lxstRemoteIdentityHash)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callStatus, remoteHash in
                self?.receive(callStatus, remoteHash: remoteHash)
            }
            .store(in: &cancellables)
    }

    func call(_ peer: LXMFPeer) {
        switch state {
        case .incoming(let incomingPeer)
            where incomingPeer.destinationHash == peer.destinationHash:
            guard bridge.answerLXSTCall() else {
                statusMessage = "The incoming LXST call could not be answered."
                return
            }
            statusMessage = "Connecting to \(incomingPeer.displayName)…"
        case .idle:
            state = .calling(peer)
            statusMessage = "Calling \(peer.displayName)…"
            Task {
                let started = await bridge.placeLXSTCall(
                    destinationHash: peer.destinationHash
                )
                if !started, case .calling = state {
                    state = .idle
                    statusMessage =
                        "The LXST call could not find or connect to that Sideband identity."
                }
            }
        default:
            statusMessage = "End the current call before starting another."
        }
    }

    func reject() {
        guard case .incoming(let peer) = state else {
            statusMessage = "There is no incoming call to reject."
            return
        }
        bridge.hangupLXSTCall(reject: true)
        IncomingCallNotificationManager.shared.clear()
        state = .idle
        statusMessage = "Call from \(peer.displayName) rejected"
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
        bridge.hangupLXSTCall()
        IncomingCallNotificationManager.shared.clear()
        state = .idle
        statusMessage = "Call with \(peer.displayName) ended"
    }

    private var isIncoming: Bool {
        if case .incoming = state { return true }
        return false
    }

    private func receive(_ callStatus: LXSTCallStatus, remoteHash: String) {
        switch callStatus {
        case .busy:
            IncomingCallNotificationManager.shared.clear()
            state = .idle
            statusMessage = "The remote Sideband device is busy."
        case .rejected:
            IncomingCallNotificationManager.shared.clear()
            state = .idle
            statusMessage = "The remote Sideband device rejected the call."
        case .calling:
            break
        case .available:
            IncomingCallNotificationManager.shared.clear()
            if state != .idle {
                state = .idle
                statusMessage = "Call ended"
            }
        case .connecting:
            if let peer = state.peer {
                statusMessage = "Connecting to \(peer.displayName)…"
            }
        case .ringing:
            if case .calling(let peer) = state {
                statusMessage = "Ringing \(peer.displayName)…"
            } else {
                let peer = peerForIncomingIdentity(remoteHash)
                state = .incoming(peer)
                statusMessage = "Incoming LXST call from \(peer.displayName)"
                IncomingCallNotificationManager.shared.notify(peer: peer)
            }
        case .established:
            IncomingCallNotificationManager.shared.clear()
            let peer = state.peer ?? peerForIncomingIdentity(remoteHash)
            state = .active(peer)
            statusMessage = "Connected to \(peer.displayName) over LXST"
        }
    }

    private func peerForIncomingIdentity(_ identityHash: String) -> LXMFPeer {
        let cleaned = identityHash.lowercased()
        let name = LXMFContactStore.shared.contact(for: cleaned)?.displayName
            ?? ReticulumDiscoveredPeerStore.shared.peers.first(where: {
                $0.identityHash == cleaned
            })?.displayName
            ?? (cleaned.isEmpty ? "Unknown Sideband Caller" : "Sideband Caller")
        return LXMFPeer(displayName: name, destinationHash: cleaned)
    }
}

struct VoiceCallView: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var peerStore = ReticulumDiscoveredPeerStore.shared
    @ObservedObject private var contactStore = LXMFContactStore.shared
    @StateObject private var callManager = VoiceCallManager.shared
    private let bridge = ReticulumCoreBridge.shared

    @State private var identityHash = ""
    @State private var validationMessage: String?
    @State private var speakerphoneEnabled = false
    @State private var microphoneMuted = false

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
                Text("Live Opus voice over the selected Reticulum interface")
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
            }

            HStack(spacing: 0) {
                TextField(
                    "LXST hash or Discovered Peer",
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

            Spacer()

            switch callManager.state {
            case .idle:
                Button {
                    startOrAcceptCall()
                } label: {
                    Text("Call")
                        .font(.headline.bold())
                        .padding(.horizontal, 36)
                        .padding(.vertical, 6)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity)
            case .calling:
                Button("Hang Up") { callManager.end() }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .frame(maxWidth: .infinity).frame(minHeight: 54).font(.headline)
            case .incoming:
                HStack(spacing: 14) {
                    Button("Reject") { callManager.reject() }
                        .buttonStyle(.borderedProminent).tint(.blue)
                    Button("Answer") { startOrAcceptCall() }
                        .buttonStyle(.borderedProminent).tint(.green).font(.headline)
                }.frame(maxWidth: .infinity)
            case .active:
                HStack(spacing: 12) {
                    Button("End") { callManager.end() }
                        .buttonStyle(.borderedProminent).tint(.red)
                    Button {
                        speakerphoneEnabled.toggle(); bridge.setLXSTSpeakerphone(speakerphoneEnabled)
                    } label: { Label(speakerphoneEnabled ? "Speaker" : "Phone", systemImage: speakerphoneEnabled ? "speaker.wave.3.fill" : "phone.fill") }
                        .buttonStyle(.borderedProminent).tint(speakerphoneEnabled ? .green : .gray)
                    Button {
                        microphoneMuted.toggle(); bridge.setLXSTMicrophoneMuted(microphoneMuted)
                    } label: { Label(microphoneMuted ? "Unmute" : "Mute", systemImage: microphoneMuted ? "mic.slash.fill" : "mic.fill") }
                        .buttonStyle(.borderedProminent).tint(microphoneMuted ? .orange : .gray)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding()
        .onAppear {
            adoptCurrentPeer()
        }
        .onChange(of: callManager.state) { _, _ in
            adoptCurrentPeer()
            if case .idle = callManager.state {
                speakerphoneEnabled = false
                microphoneMuted = false
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
                if case .active = callManager.state {
                    Text(bridge.lxstAudioStatus)
                        .font(.caption)
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
            ?? peerStore.peers.first(where: {
                $0.destinationHash == cleaned || $0.identityHash == cleaned
            })?.displayName
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
