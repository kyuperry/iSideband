import Foundation

enum ReticulumDecoderSelfTest {

    static func run() {
        do {
            let samplePacket = makeSampleAnnouncePacket()

            let decoder = ReticulumPacketDecoder()
            let decodedPacket = try decoder.decode(samplePacket)

            privacySafeLog(
                """
                RETICULUM DECODER SELF-TEST PASSED
                Type: \(decodedPacket.packetType)
                Destination: \(decodedPacket.destinationHashHex)
                Hops: \(decodedPacket.hops)
                Context: \(decodedPacket.contextRawValue)
                Payload bytes: \(decodedPacket.payload.count)
                """
            )

            assert(decodedPacket.packetType == .announce)
            assert(decodedPacket.headerType == .normal)
            assert(decodedPacket.destinationType == .single)
            assert(decodedPacket.destinationHash.count == 16)
            assert(decodedPacket.payload == Data([0xAA, 0xBB, 0xCC]))

        } catch {
            privacySafeLog(
                "RETICULUM DECODER SELF-TEST FAILED:",
                error.localizedDescription
            )
        }
    }

    private static func makeSampleAnnouncePacket() -> Data {
        /*
         Synthetic packet for testing our decoder only:

         Byte 0:
         - Normal header
         - Broadcast transport
         - Single destination
         - Announce packet

         Byte 1:
         - Zero hops

         Next 16 bytes:
         - Example destination hash

         Next byte:
         - Context 0x00

         Remaining bytes:
         - Example payload
         */

        let flags: UInt8 =
            (ReticulumHeaderType.normal.rawValue << 6)
            | (ReticulumTransportType.broadcast.rawValue << 4)
            | (ReticulumDestinationType.single.rawValue << 2)
            | ReticulumPacketType.announce.rawValue

        var packet = Data([
            flags,
            0x00
        ])

        packet.append(
            contentsOf: [
                0x00, 0x01, 0x02, 0x03,
                0x04, 0x05, 0x06, 0x07,
                0x08, 0x09, 0x0A, 0x0B,
                0x0C, 0x0D, 0x0E, 0x0F
            ]
        )

        packet.append(
            ReticulumPacketContext.none.rawValue
        )

        packet.append(
            contentsOf: [
                0xAA,
                0xBB,
                0xCC
            ]
        )

        return packet
    }
}
