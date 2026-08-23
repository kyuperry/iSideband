import AVFoundation
import Combine
import SwiftUI

enum PushToTalkPreferenceKey {
    static let enabled = "pushToTalkButtonEnabled"
}

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    static let maximumDuration: TimeInterval = 15
    private static let sampleRate = 16_000
    private static let opusBitRate = 16_000
    private static let minimumRecordingBytes = 64
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var pendingStartID: UUID?
    private var hasFinalizedCurrentRecording = false
    private(set) var outputURL: URL?

    func start() {
        errorMessage = nil
        let startID = UUID()
        pendingStartID = startID
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                guard pendingStartID == startID else { return }
                pendingStartID = nil
                errorMessage = "Microphone access is required. Enable it in Settings."
                return
            }
            guard pendingStartID == startID else { return }
            pendingStartID = nil
            beginRecording()
        }
    }

    func stop() -> URL? {
        pendingStartID = nil
        guard isRecording else { return outputURL }
        recorder?.stop()
        finishRecording()
        return outputURL
    }

    func cancel() {
        pendingStartID = nil
        recorder?.stop()
        finishRecording()
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
    }

    private func beginRecording() {
        do {
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = root.appendingPathComponent("DirectAttachments", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identifier = UUID().uuidString
            let recordingURL = directory.appendingPathComponent("voice-\(identifier).caf")
            let outputURL = directory.appendingPathComponent("voice-\(identifier).ogg")
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatOpus),
                // Sideband-compatible Ogg/Opus, tuned for speech over LoRa.
                // At 16 kbps, a full 15-second note is approximately 30 KB
                // before the small Ogg container overhead.
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: Self.opusBitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder.delegate = self
            guard recorder.prepareToRecord() else {
                throw RecorderError.couldNotStart
            }
            guard recorder.record(forDuration: Self.maximumDuration) else {
                throw RecorderError.couldNotStart
            }
            self.recorder = recorder
            self.outputURL = outputURL
            hasFinalizedCurrentRecording = false
            elapsed = 0
            isRecording = true
            timer = .scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed = min(recorder.currentTime, Self.maximumDuration)
                    if !recorder.isRecording { self.finishRecording() }
                }
            }
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func finishRecording() {
        guard !hasFinalizedCurrentRecording else { return }
        hasFinalizedCurrentRecording = true
        timer?.invalidate()
        timer = nil
        isRecording = false
        let recordingURL = recorder?.url
        recorder = nil
        if let recordingURL, let outputURL {
            do {
                try OpusOggMuxer.convert(cafURL: recordingURL, to: outputURL)
                try? FileManager.default.removeItem(at: recordingURL)
                let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
                guard data.count >= Self.minimumRecordingBytes,
                      data.starts(with: Data("OggS".utf8)) else {
                    throw RecorderError.emptyRecording
                }
            } catch {
                try? FileManager.default.removeItem(at: recordingURL)
                try? FileManager.default.removeItem(at: outputURL)
                self.outputURL = nil
                errorMessage = "The voice recording could not be completed: \(error.localizedDescription)"
            }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            finishRecording()
            if !flag { errorMessage = "The voice recording could not be completed." }
        }
    }

    private enum RecorderError: LocalizedError {
        case couldNotStart
        case emptyRecording
        var errorDescription: String? {
            switch self {
            case .couldNotStart: "The microphone did not start."
            case .emptyRecording: "The voice recording was empty."
            }
        }
    }
}

struct VoiceNoteRecorderView: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceNoteRecorder()
    @State private var isHoldingPushToTalk = false
    let isPushToTalk: Bool
    let onSend: (URL) -> Void

    init(
        isPushToTalk: Bool = false,
        onSend: @escaping (URL) -> Void
    ) {
        self.isPushToTalk = isPushToTalk
        self.onSend = onSend
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : (recorder.isRecording ? Color.red : Color.accentColor)
                    )
                Text(String(format: "0:%02d", Int(recorder.elapsed)))
                    .font(.system(.title, design: .monospaced).bold())
                Text(
                    isPushToTalk
                        ? "Push-to-Talk records while the red button is held, stops when released, and uses low-bandwidth Opus for reliable radio transfers."
                        : "Voice messages stop after 15 seconds and use low-bandwidth Opus for reliable radio transfers."
                )
                    .font(.footnote)
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.secondary
                            : .secondary
                    )
                    .multilineTextAlignment(.center)

                if isPushToTalk {
                    pushToTalkRecordControl
                } else {
                    Button(recorder.isRecording ? "Stop Recording" : "Start Recording") {
                        if recorder.isRecording {
                            _ = recorder.stop()
                        } else {
                            recorder.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .nightVisionProminentButton()
                }

                if !recorder.isRecording, let url = recorder.outputURL {
                    Button(
                        isPushToTalk ? "Send Push-to-Talk" : "Send Voice Message"
                    ) { onSend(url); dismiss() }
                        .buttonStyle(.borderedProminent)
                        .nightVisionProminentButton()
                }
            }
            .padding(28)
            .navigationTitle(isPushToTalk ? "Push-to-Talk" : "Voice Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { recorder.cancel(); dismiss() }
                }
            }
            .alert("Recording Unavailable", isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(recorder.errorMessage ?? "") }
        }
        .interactiveDismissDisabled(
            recorder.isRecording || isHoldingPushToTalk
        )
    }

    private var pushToTalkRecordControl: some View {
        Label(
            isHoldingPushToTalk ? "Recording… Release to Stop" : "Hold to Record",
            systemImage: isHoldingPushToTalk ? "waveform" : "mic.fill"
        )
        .font(.headline.weight(.semibold))
        .foregroundStyle(
            isNightVisionEnabled
                ? NightVisionPalette.primary
                : .white
        )
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
        .background(
            isNightVisionEnabled
                ? NightVisionPalette.strongSurface
                : Color.red,
            in: Capsule()
        )
        .scaleEffect(isHoldingPushToTalk ? 0.96 : 1)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHoldingPushToTalk else { return }
                    isHoldingPushToTalk = true
                    recorder.start()
                }
                .onEnded { _ in
                    guard isHoldingPushToTalk else { return }
                    isHoldingPushToTalk = false
                    _ = recorder.stop()
                }
        )
        .accessibilityLabel("Hold to record Push-to-Talk")
        .accessibilityHint("Recording stops when you release the button")
    }
}

@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private var player: AVAudioPlayer?
    private var opusPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func toggle(url: URL) {
        if isPlaying {
            player?.stop()
            opusPlayer?.pause()
            isPlaying = false
            return
        }
        errorMessage = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)

            if url.pathExtension.lowercased() == "ogg" {
                playOpus(url: url)
                return
            }

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.volume = 1
            guard player?.prepareToPlay() == true,
                  player?.play() == true else {
                throw PlaybackError.couldNotStart
            }
            isPlaying = true
        } catch {
            isPlaying = false
            errorMessage = "Could not play audio: \(error.localizedDescription)"
            privacySafeLog("VOICE PLAYBACK FAILED: \(error)")
        }
    }

    private func playOpus(url: URL) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1
        opusPlayer = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
        player.play()
        isPlaying = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard item.status == .failed else { return }
            isPlaying = false
            errorMessage = "This iPhone could not decode the Sideband Ogg/Opus audio."
            privacySafeLog("VOICE OPUS PLAYBACK FAILED: \(item.error?.localizedDescription ?? "unknown error")")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in isPlaying = false }
    }

    private enum PlaybackError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "The audio decoder did not start." }
    }
}
