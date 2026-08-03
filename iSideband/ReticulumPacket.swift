import Foundation

enum ReticulumPacketType: UInt8 {
    case data = 0x00
    case announce = 0x01
    case linkRequest = 0x02
    case proof = 0x03
}

enum ReticulumHeaderType: UInt8 {
    case normal = 0x00
    case transport = 0x01
}

enum ReticulumTransportType: UInt8 {
    case broadcast = 0x00
    case transport = 0x01
}

enum ReticulumDestinationType: UInt8 {
    case single = 0x00
    case group = 0x01
    case plain = 0x02
    case link = 0x03
}

enum ReticulumPacketContext: UInt8 {
    case none = 0x00
    case resource = 0x01
    case resourceAdvertisement = 0x02
    case resourceRequest = 0x03
    case resourceHashmapUpdate = 0x04
    case resourceProof = 0x05
    case resourceInitiatorCancel = 0x06
    case resourceReceiverCancel = 0x07
    case cacheRequest = 0x08
    case request = 0x09
    case response = 0x0A
    case pathResponse = 0x0B
    case command = 0x0C
    case commandStatus = 0x0D
    case channel = 0x0E
    case keepalive = 0xFA
    case linkIdentify = 0xFB
    case linkClose = 0xFC
    case linkProof = 0xFD
    case linkRequestRoundTripTime = 0xFE
    case linkRequestProof = 0xFF
}

struct ReticulumPacket {
    let destinationHash: Data
    let payload: Data

    let packetType: ReticulumPacketType
    let headerType: ReticulumHeaderType
    let transportType: ReticulumTransportType
    let destinationType: ReticulumDestinationType
    let context: ReticulumPacketContext

    init(
        destinationHash: Data,
        payload: Data,
        packetType: ReticulumPacketType = .data,
        headerType: ReticulumHeaderType = .normal,
        transportType: ReticulumTransportType = .broadcast,
        destinationType: ReticulumDestinationType = .single,
        context: ReticulumPacketContext = .none
    ) throws {
        guard destinationHash.count ==
                ReticulumPacketEncoder.destinationHashByteCount
        else {
            throw ReticulumEncodingError.invalidDestinationHash
        }

        guard !payload.isEmpty else {
            throw ReticulumEncodingError.emptyMessage
        }

        self.destinationHash = destinationHash
        self.payload = payload
        self.packetType = packetType
        self.headerType = headerType
        self.transportType = transportType
        self.destinationType = destinationType
        self.context = context
    }

    var packedFlags: UInt8 {
        (headerType.rawValue << 6)
            | (transportType.rawValue << 4)
            | (destinationType.rawValue << 2)
            | packetType.rawValue
    }

    func encode() throws -> Data {
        throw ReticulumEncodingError.protocolNotImplemented
    }
}
