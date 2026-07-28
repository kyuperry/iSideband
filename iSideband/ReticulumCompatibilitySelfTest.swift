import Foundation

enum ReticulumCompatibilitySelfTest {
    static func run() {
        #if DEBUG
        do {
            let local = try ReticulumIdentity.generate()
            let remote = try ReticulumIdentity.generate()
            let announceEncoder =
                ReticulumAnnounceEncoder()
            let localDestination =
                try announceEncoder.destinationHash(
                    identity: local,
                    destinationName: "lxmf.delivery"
                )
            let remoteDestination =
                try announceEncoder.destinationHash(
                    identity: remote,
                    destinationName: "lxmf.delivery"
                )
            let codec = LXMFMessageCodec()
            let lxmf = try codec.encode(
                content: "Compatibility self-test",
                destinationHash: localDestination,
                sourceHash: remoteDestination,
                sourceIdentity: remote
            )
            let encrypted = try remote.encrypt(
                lxmf,
                for: local.publicKey
            )
            let rawPacket =
                try ReticulumPacketEncoder()
                    .encodeDataPacket(
                        destinationHash:
                            localDestination,
                        encryptedPayload: encrypted
                    )
            let packet =
                try ReticulumPacketDecoder()
                    .decode(rawPacket)
            let plaintext =
                try local.decrypt(packet.payload)
            let message = try codec.decode(
                plaintext,
                expectedDestinationHash:
                    localDestination
            ) { sourceHash in
                sourceHash ==
                    remoteDestination.hexString
                    ? remote.publicKey
                    : nil
            }

            precondition(
                message.content ==
                    "Compatibility self-test"
            )

            var tampered = packet.payload
            tampered[
                tampered.index(before: tampered.endIndex)
            ] ^= 0x01

            do {
                _ = try local.decrypt(tampered)
                preconditionFailure(
                    "Tampered Reticulum token was accepted"
                )
            } catch {
            }

            print(
                """
                RETICULUM/LXMF COMPATIBILITY SELF-TEST PASSED
                Encryption, packet framing, MessagePack and signature validation are operational.
                """
            )
        } catch {
            preconditionFailure(
                "Reticulum/LXMF compatibility self-test failed: \(error)"
            )
        }
        #endif
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
