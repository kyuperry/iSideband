import AudioToolbox
import Foundation

/// Repackages the Opus packets produced by AVAudioRecorder into the Ogg
/// container used by Sideband. No audio is decoded or re-encoded here.
enum OpusOggMuxer {
    enum MuxError: LocalizedError {
        case couldNotOpen(OSStatus)
        case property(OSStatus)
        case notOpus
        case noAudio
        case packet(OSStatus)
        case malformedPacket

        var errorDescription: String? {
            switch self {
            case .couldNotOpen(let status): "Could not open the recorded audio (\(status))."
            case .property(let status): "Could not inspect the recorded audio (\(status))."
            case .notOpus: "The recording was not encoded as Opus."
            case .noAudio: "The recording did not contain any audio."
            case .packet(let status): "Could not read the recorded audio (\(status))."
            case .malformedPacket: "The Opus recording was incomplete."
            }
        }
    }

    static func convert(cafURL: URL, to oggURL: URL) throws {
        var audioFile: AudioFileID?
        let openStatus = AudioFileOpenURL(
            cafURL as CFURL,
            .readPermission,
            0,
            &audioFile
        )
        guard openStatus == noErr, let audioFile else {
            throw MuxError.couldNotOpen(openStatus)
        }
        defer { AudioFileClose(audioFile) }

        var format = AudioStreamBasicDescription()
        try readProperty(audioFile, id: kAudioFilePropertyDataFormat, into: &format)
        guard format.mFormatID == kAudioFormatOpus else { throw MuxError.notOpus }

        var packetCount: UInt64 = 0
        try readProperty(audioFile, id: kAudioFilePropertyAudioDataPacketCount, into: &packetCount)
        guard packetCount > 0 else { throw MuxError.noAudio }

        var maximumPacketSize: UInt32 = 0
        try readProperty(audioFile, id: kAudioFilePropertyMaximumPacketSize, into: &maximumPacketSize)
        guard maximumPacketSize > 0 else { throw MuxError.noAudio }

        let channelCount = UInt8(clamping: Int(format.mChannelsPerFrame))
        var packets: [Data] = []
        packets.reserveCapacity(Int(packetCount))
        var packetDurations: [UInt64] = []
        packetDurations.reserveCapacity(Int(packetCount))

        var buffer = Data(count: Int(maximumPacketSize))
        for index in 0..<packetCount {
            var bytes = maximumPacketSize
            var packetsRead: UInt32 = 1
            var description = AudioStreamPacketDescription()
            let status = buffer.withUnsafeMutableBytes { rawBuffer in
                AudioFileReadPacketData(
                    audioFile,
                    false,
                    &bytes,
                    &description,
                    Int64(index),
                    &packetsRead,
                    rawBuffer.baseAddress!
                )
            }
            guard status == noErr else { throw MuxError.packet(status) }
            guard packetsRead == 1, bytes > 0 else { throw MuxError.malformedPacket }
            let start = max(0, Int(description.mStartOffset))
            let length = description.mDataByteSize > 0 ? Int(description.mDataByteSize) : Int(bytes)
            guard start + length <= buffer.count else { throw MuxError.malformedPacket }
            let packet = buffer.subdata(in: start..<(start + length))
            packets.append(packet)
            packetDurations.append(try durationAt48k(of: packet))
        }

        var output = Data()
        let serial = UInt32.random(in: UInt32.min...UInt32.max)
        var sequence: UInt32 = 0

        var opusHead = Data("OpusHead".utf8)
        opusHead.append(1) // OpusHead version
        opusHead.append(channelCount)
        opusHead.appendLE(UInt16(0)) // Preserve the complete short recording.
        opusHead.appendLE(UInt32(clamping: Int(format.mSampleRate)))
        opusHead.appendLE(UInt16(0)) // Output gain
        opusHead.append(0) // Mono/stereo channel mapping family
        output.append(page(packet: opusHead, headerType: 0x02, granule: 0, serial: serial, sequence: sequence))
        sequence += 1

        let vendor = Data("iSideband".utf8)
        var opusTags = Data("OpusTags".utf8)
        opusTags.appendLE(UInt32(vendor.count))
        opusTags.append(vendor)
        opusTags.appendLE(UInt32(0))
        output.append(page(packet: opusTags, headerType: 0, granule: 0, serial: serial, sequence: sequence))
        sequence += 1

        var granule: UInt64 = 0
        for (index, packet) in packets.enumerated() {
            granule += packetDurations[index]
            let isLast = index == packets.count - 1
            output.append(page(
                packet: packet,
                headerType: isLast ? 0x04 : 0,
                granule: granule,
                serial: serial,
                sequence: sequence
            ))
            sequence += 1
        }

        try output.write(to: oggURL, options: .atomic)
    }

    private static func readProperty<T>(
        _ file: AudioFileID,
        id: AudioFilePropertyID,
        into value: inout T
    ) throws {
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioFileGetProperty(file, id, &size, &value)
        guard status == noErr else { throw MuxError.property(status) }
    }

    private static func durationAt48k(of packet: Data) throws -> UInt64 {
        guard let toc = packet.first else { throw MuxError.malformedPacket }
        let samplesPerFrame: Int
        if toc & 0x80 != 0 {
            samplesPerFrame = (48_000 << Int((toc >> 3) & 0x03)) / 400
        } else if toc & 0x60 == 0x60 {
            samplesPerFrame = toc & 0x08 != 0 ? 48_000 / 50 : 48_000 / 100
        } else {
            samplesPerFrame = (48_000 << Int((toc >> 3) & 0x03)) / 100
        }

        let frameCount: Int
        switch toc & 0x03 {
        case 0: frameCount = 1
        case 1, 2: frameCount = 2
        default:
            guard packet.count >= 2 else { throw MuxError.malformedPacket }
            frameCount = Int(packet[packet.startIndex + 1] & 0x3f)
            guard frameCount > 0 else { throw MuxError.malformedPacket }
        }
        let duration = samplesPerFrame * frameCount
        guard duration <= 5_760 else { throw MuxError.malformedPacket }
        return UInt64(duration)
    }

    private static func page(
        packet: Data,
        headerType: UInt8,
        granule: UInt64,
        serial: UInt32,
        sequence: UInt32
    ) -> Data {
        var lacing = [UInt8](repeating: 255, count: packet.count / 255)
        lacing.append(UInt8(packet.count % 255))

        var result = Data("OggS".utf8)
        result.append(0)
        result.append(headerType)
        result.appendLE(granule)
        result.appendLE(serial)
        result.appendLE(sequence)
        result.appendLE(UInt32(0))
        result.append(UInt8(lacing.count))
        result.append(contentsOf: lacing)
        result.append(packet)

        let checksum = oggCRC(result)
        result.replaceSubrange(22..<26, with: checksum.littleEndianBytes)
        return result
    }

    private static func oggCRC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                crc = (crc & 0x8000_0000) != 0
                    ? (crc << 1) ^ 0x04c1_1db7
                    : crc << 1
            }
        }
        return crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        append(contentsOf: value.littleEndianBytes)
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}
