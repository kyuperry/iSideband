import AVFoundation
import AudioToolbox
import Foundation

/// Live Opus audio for LXST's medium-quality telephony profile.
///
/// LXST medium quality is mono Opus at 24 kHz with 60 ms frames and an
/// 8 kbit/s ceiling. All converter and buffering work is serialized because
/// AVAudioConverter instances are not safe to use concurrently.
final class LXSTAudioEngine: @unchecked Sendable {
    typealias FrameSender = @Sendable (Data) -> Void
    typealias StatusHandler = @Sendable (String) -> Void

    private let audioQueue = DispatchQueue(
        label: "com.kyleperry.iSideband.lxst.audio",
        qos: .userInteractive
    )
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let frameSender: FrameSender
    private let statusHandler: StatusHandler

    private let sampleRate = 24_000.0
    private let samplesPerFrame: AVAudioFrameCount = 1_440
    private var captureConverter: AVAudioConverter?
    private var encoder: AVAudioConverter?
    private var decoder: AVAudioConverter?
    private var pendingSamples = [Float]()
    private var isRunning = false
    private var isMuted = false
    private var didReportTransmit = false
    private var didReportReceive = false

    private lazy var pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    private lazy var opusFormat: AVAudioFormat? = AVAudioFormat(settings: [
        AVFormatIDKey: kAudioFormatOpus,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 8_000
    ])

    init(
        frameSender: @escaping FrameSender,
        statusHandler: @escaping StatusHandler
    ) {
        self.frameSender = frameSender
        self.statusHandler = statusHandler
    }

    func start() {
        report("Starting call audio…")
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            if !granted {
                self?.report("Microphone denied — receive audio only")
            }
            self?.audioQueue.async {
                self?.startAudio(captureEnabled: granted)
            }
        }
    }

    func stop() {
        audioQueue.async { [weak self] in self?.stopAudio() }
    }

    func setMuted(_ muted: Bool) {
        audioQueue.async { [weak self] in self?.isMuted = muted }
    }

    func receiveOpusFrame(_ data: Data) {
        guard !data.isEmpty else { return }
        audioQueue.async { [weak self] in self?.decodeAndPlay(data) }
    }

    private func startAudio(captureEnabled: Bool) {
        guard !isRunning else { return }
        guard let opusFormat else {
            report("Opus audio format unavailable")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: pcmFormat)

            guard let decoder = AVAudioConverter(
                      from: opusFormat,
                      to: pcmFormat
                  ) else {
                throw LXSTAudioError.converterUnavailable
            }
            self.decoder = decoder
            pendingSamples.removeAll(keepingCapacity: true)
            didReportTransmit = false
            didReportReceive = false

            if captureEnabled {
                let input = engine.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0,
                      inputFormat.channelCount > 0,
                      let captureConverter = AVAudioConverter(
                          from: inputFormat,
                          to: pcmFormat
                      ),
                      let encoder = AVAudioConverter(
                          from: pcmFormat,
                          to: opusFormat
                      ) else {
                    throw LXSTAudioError.converterUnavailable
                }
                self.captureConverter = captureConverter
                self.encoder = encoder
                input.installTap(
                    onBus: 0,
                    bufferSize: 960,
                    format: inputFormat
                ) { [weak self] buffer, _ in
                    self?.audioQueue.async {
                        self?.capture(buffer, from: inputFormat)
                    }
                }
            }

            engine.prepare()
            try engine.start()
            player.play()
            isRunning = true
            report(captureEnabled ? "Call audio ready" : "Receive audio ready")
        } catch {
            privacySafeLog("LXST audio could not start", error.localizedDescription)
            report("Audio failed: \(error.localizedDescription)")
            stopAudio()
        }
    }

    private func stopAudio() {
        guard isRunning || engine.isRunning else { return }
        if captureConverter != nil {
            engine.inputNode.removeTap(onBus: 0)
        }
        player.stop()
        engine.stop()
        engine.reset()
        captureConverter = nil
        encoder = nil
        decoder = nil
        pendingSamples.removeAll(keepingCapacity: false)
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func capture(
        _ inputBuffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat
    ) {
        guard isRunning,
              !isMuted,
              let captureConverter,
              let converted = AVAudioPCMBuffer(
                  pcmFormat: pcmFormat,
                  frameCapacity: AVAudioFrameCount(
                      ceil(
                          Double(inputBuffer.frameLength)
                              * sampleRate / inputFormat.sampleRate
                      )
                  ) + 8
              ) else { return }

        var supplied = false
        var conversionError: NSError?
        let status = captureConverter.convert(
            to: converted,
            error: &conversionError
        ) { _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error,
              conversionError == nil,
              let channel = converted.floatChannelData?[0] else { return }

        pendingSamples.append(
            contentsOf: UnsafeBufferPointer(
                start: channel,
                count: Int(converted.frameLength)
            )
        )
        while pendingSamples.count >= Int(samplesPerFrame) {
            let samples = Array(pendingSamples.prefix(Int(samplesPerFrame)))
            pendingSamples.removeFirst(Int(samplesPerFrame))
            encode(samples)
        }
    }

    private func encode(_ samples: [Float]) {
        guard let encoder,
              let opusFormat,
              let pcm = AVAudioPCMBuffer(
                  pcmFormat: pcmFormat,
                  frameCapacity: samplesPerFrame
              ),
              let channel = pcm.floatChannelData?[0] else { return }
        pcm.frameLength = samplesPerFrame
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }

        let compressed = AVAudioCompressedBuffer(
            format: opusFormat,
            packetCapacity: 1,
            maximumPacketSize: 1_275
        )
        var supplied = false
        var error: NSError?
        let status = encoder.convert(to: compressed, error: &error) {
            _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return pcm
        }
        guard status != .error,
              error == nil,
              compressed.byteLength > 0 else { return }
        frameSender(
            Data(
                bytes: compressed.data,
                count: Int(compressed.byteLength)
            )
        )
        if !didReportTransmit {
            didReportTransmit = true
            report("Sending live Opus audio")
        }
    }

    private func decodeAndPlay(_ data: Data) {
        guard isRunning,
              let decoder,
              let opusFormat else { return }
        let compressed = AVAudioCompressedBuffer(
            format: opusFormat,
            packetCapacity: 1,
            maximumPacketSize: data.count
        )
        data.copyBytes(
            to: compressed.data.assumingMemoryBound(to: UInt8.self),
            count: data.count
        )
        compressed.byteLength = UInt32(data.count)
        compressed.packetCount = 1
        if let descriptions = compressed.packetDescriptions {
            descriptions[0] = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: samplesPerFrame,
                mDataByteSize: UInt32(data.count)
            )
        }

        guard let pcm = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: samplesPerFrame
        ) else { return }
        var supplied = false
        var error: NSError?
        let status = decoder.convert(to: pcm, error: &error) {
            _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return compressed
        }
        guard status != .error,
              error == nil,
              pcm.frameLength > 0 else { return }
        player.scheduleBuffer(pcm)
        if !player.isPlaying { player.play() }
        if !didReportReceive {
            didReportReceive = true
            report("Receiving live Opus audio")
        }
    }

    private func report(_ status: String) {
        statusHandler(status)
    }
}

private enum LXSTAudioError: LocalizedError {
    case converterUnavailable

    var errorDescription: String? {
        "The system Opus audio converter is unavailable."
    }
}
