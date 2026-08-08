import AVFoundation
import Combine
import SwiftUI

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var outputURL: URL?

    static let maximumDuration: TimeInterval = 60

    func start() {
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                errorMessage = "Microphone access is required to record a voice message. You can enable it in Settings."
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
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
    }

    private func beginRecording() {
        do {
            let directory = try Self.attachmentDirectory()
            let url = directory.appendingPathComponent(
                "voice-\(UUID().uuidString).m4a"
            )
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            guard recorder.record(forDuration: Self.maximumDuration) else {
                throw VoiceNoteError.couldNotStart
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

    private static func attachmentDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("DirectAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private enum VoiceNoteError: LocalizedError {
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
                    .symbolEffect(.pulse, isActive: recorder.isRecording)

                Text(durationText)
                    .font(.system(.title, design: .monospaced).bold())

                Text("Voice messages stop automatically after one minute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    if recorder.isRecording {
                        _ = recorder.stop()
                    } else {
                        recorder.start()
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop Recording" : "Start Recording",
                          systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .accentColor)

                if !recorder.isRecording, let url = recorder.outputURL {
                    Button("Send Voice Message") {
                        onSend(url)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .navigationTitle("Voice Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
            .alert("Recording Unavailable", isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(recorder.isRecording)
    }

    private var durationText: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            player?.stop()
            isPlaying = false
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in isPlaying = false }
    }
}
