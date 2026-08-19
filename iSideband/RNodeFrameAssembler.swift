import Foundation

final class RNodeFrameAssembler {
    private let frameBoundary: UInt8 = 0xC0
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        buffer.append(data)

        var frames: [Data] = []
        var frameStartIndex: Data.Index?

        var index = buffer.startIndex

        while index < buffer.endIndex {
            if buffer[index] == frameBoundary {
                if let startIndex = frameStartIndex {
                    let frame = Data(buffer[startIndex...index])

                    if frame.count > 2 {
                        frames.append(frame)
                        privacySafeLog("Frame assembled: \(frame as NSData)")
                    }
                    frameStartIndex = index
                } else {
                    frameStartIndex = index
                }
            }

            index = buffer.index(after: index)
        }

        if let frameStartIndex {
            buffer = Data(buffer[frameStartIndex...])
        } else {
            buffer.removeAll()
        }

        return frames
    }

    func reset() {
        buffer.removeAll()
    }
}
