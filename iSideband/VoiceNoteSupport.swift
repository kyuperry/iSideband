import AVFoundation
import Combine
import SwiftUI

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    static let maximumDuration: TimeInterval = 15
    private static let sampleRate = 12_000
    private static let opusBitRate = 8_000
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var outputURL: URL?

    func start() {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                errorMessage = "Microphone access is required. Enable it in Settings."
                return
            }
            beginRecording()
        }
    }

    func stop() -> URL? {
        guard isRecording else { return outputURL }
        recorder?.stop()
        finishRecording()
        return outputURL
    }

    func cancel() {
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
            let url = directory.appendingPathComponent("voice-\(UUID().uuidString).ogg")
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatOpus),
                // Sideband-compatible Ogg/Opus, tuned for speech over LoRa.
                // At 8 kbps, a full 15-second note is approximately 15 KB
                // before the small Ogg container overhead.
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: Self.opusBitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            guard recorder.record(forDuration: Self.maximumDuration) else {
                throw RecorderError.couldNotStart
            }
            self.recorder = recorder
            outputURL = url
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
        timer?.invalidate()
        timer = nil
        isRecording = false
        recorder = nil
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
        var errorDescription: String? { "The microphone did not start." }
    }
}

struct VoiceNoteRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceNoteRecorder()
    let onSend: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor)
                Text(String(format: "0:%02d", Int(recorder.elapsed)))
                    .font(.system(.title, design: .monospaced).bold())
                Text("Voice messages stop after 15 seconds and use low-bandwidth Opus for reliable radio transfers.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(recorder.isRecording ? "Stop Recording" : "Start Recording") {
                    if recorder.isRecording {
                        _ = recorder.stop()
                    } else {
                        recorder.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                if !recorder.isRecording, let url = recorder.outputURL {
                    Button("Send Voice Message") { onSend(url); dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .navigationTitle("Voice Message")
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
        .interactiveDismissDisabled(recorder.isRecording)
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
            print("VOICE PLAYBACK FAILED: \(error)")
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
            print("VOICE OPUS PLAYBACK FAILED: \(item.error?.localizedDescription ?? "unknown error")")
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
