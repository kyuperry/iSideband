import Foundation

struct RNodeRadioConfiguration: Equatable {
    let frequencyHz: UInt32
    let bandwidthHz: UInt32
    let transmitPowerDBm: Int
    let spreadingFactor: Int
    let codingRate: Int

    var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000
    }

    var bandwidthKHz: Double {
        Double(bandwidthHz) / 1_000
    }
}

enum RNodeRadioConfigurationError: LocalizedError {
    case rnodeNotConnected
    case invalidFrequency
    case invalidBandwidth
    case invalidTransmitPower
    case invalidSpreadingFactor
    case invalidCodingRate
    case radioLocked
    case radioDidNotStart(String?)

    var errorDescription: String? {
        switch self {
        case .rnodeNotConnected:
            return "Connect an RNode before applying radio settings."

        case .invalidFrequency:
            return "Frequency must be between 137 and 1,020 MHz."

        case .invalidBandwidth:
            return "Bandwidth must be between 7.8 and 500 kHz."

        case .invalidTransmitPower:
            return "Transmit power must be between 0 and 30 dBm."

        case .invalidSpreadingFactor:
            return "Spreading factor must be between 5 and 12."

        case .invalidCodingRate:
            return "Coding rate must be between 5 and 8."

        case .radioLocked:
            return "The RNode radio is locked because its modem configuration is incomplete."

        case .radioDidNotStart(let detail):
            return detail ?? "The RNode did not turn its LoRa radio on."
        }
    }
}

extension BluetoothManager {
    func applyRadioConfiguration(
        _ configuration: RNodeRadioConfiguration,
        completion: @escaping (
            Result<RNodeRadioConfiguration, Error>
        ) -> Void
    ) {
        radioReady = false
        radioLocked = nil
        radioErrorMessage = nil

        guard connectedDeviceID != nil else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .rnodeNotConnected
                )
            )
            return
        }

        guard
            configuration.frequencyHz >= 137_000_000,
            configuration.frequencyHz <= 1_020_000_000
        else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .invalidFrequency
                )
            )
            return
        }

        guard
            configuration.bandwidthHz >= 7_800,
            configuration.bandwidthHz <= 500_000
        else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .invalidBandwidth
                )
            )
            return
        }

        guard
            (0...30).contains(
                configuration.transmitPowerDBm
            )
        else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .invalidTransmitPower
                )
            )
            return
        }

        guard
            (5...12).contains(
                configuration.spreadingFactor
            )
        else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .invalidSpreadingFactor
                )
            )
            return
        }

        guard
            (5...8).contains(
                configuration.codingRate
            )
        else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .invalidCodingRate
                )
            )
            return
        }

        let frequencyBytes =
            Self.bigEndianBytes(
                configuration.frequencyHz
            )

        let bandwidthBytes =
            Self.bigEndianBytes(
                configuration.bandwidthHz
            )

        let frames: [Data] = [
            // Start or refresh the active RNode host session.
            Data([
                0xC0,
                0x08,
                0x73,
                0xC0
            ]),

            // Frequency in Hz.
            Data([
                0xC0,
                0x01,
                frequencyBytes[0],
                frequencyBytes[1],
                frequencyBytes[2],
                frequencyBytes[3],
                0xC0
            ]),

            // Bandwidth in Hz.
            Data([
                0xC0,
                0x02,
                bandwidthBytes[0],
                bandwidthBytes[1],
                bandwidthBytes[2],
                bandwidthBytes[3],
                0xC0
            ]),

            // Transmit power in dBm.
            Data([
                0xC0,
                0x03,
                UInt8(
                    configuration.transmitPowerDBm
                ),
                0xC0
            ]),

            // Spreading factor.
            Data([
                0xC0,
                0x04,
                UInt8(
                    configuration.spreadingFactor
                ),
                0xC0
            ]),

            // Coding-rate denominator.
            // 6 means coding rate 4/6.
            Data([
                0xC0,
                0x05,
                UInt8(
                    configuration.codingRate
                ),
                0xC0
            ]),

            // Enable the LoRa radio.
            Data([
                0xC0,
                0x06,
                0x01,
                0xC0
            ])
        ]

        sendRadioConfigurationFrames(
            frames,
            index: 0,
            configuration: configuration,
            retryCount: 0,
            completion: completion
        )
    }

    private func sendRadioConfigurationFrames(
        _ frames: [Data],
        index: Int,
        configuration: RNodeRadioConfiguration,
        retryCount: Int,
        completion: @escaping (
            Result<RNodeRadioConfiguration, Error>
        ) -> Void
    ) {
        guard connectedDeviceID != nil else {
            completion(
                .failure(
                    RNodeRadioConfigurationError
                        .rnodeNotConnected
                )
            )
            return
        }

        guard index < frames.count else {
            /*
             These values represent the configuration just sent.
             Incoming RNode responses may update them again.
             */
            radioFrequency =
                configuration.frequencyHz

            radioBandwidth =
                configuration.bandwidthHz

            transmitPower =
                configuration.transmitPowerDBm

            spreadingFactor =
                configuration.spreadingFactor

            codingRate =
                configuration.codingRate

            print(
                """
                RNode radio configuration sent
                Frequency: \(configuration.frequencyHz) Hz
                Bandwidth: \(configuration.bandwidthHz) Hz
                TX power: \(configuration.transmitPowerDBm) dBm
                Spreading factor: \(configuration.spreadingFactor)
                Coding rate: 4/\(configuration.codingRate)
                """
            )

            verifyRadioStarted(
                configuration: configuration,
                retryCount: retryCount,
                completion: completion
            )

            return
        }

        sendToRNode(frames[index])

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.25
        ) {
            self.sendRadioConfigurationFrames(
                frames,
                index: index + 1,
                configuration: configuration,
                retryCount: retryCount,
                completion: completion
            )
        }
    }

    private func verifyRadioStarted(
        configuration: RNodeRadioConfiguration,
        retryCount: Int,
        completion: @escaping (
            Result<RNodeRadioConfiguration, Error>
        ) -> Void
    ) {
        // Ask for both the lock and state after the firmware has had time to
        // initialize the modem. These responses are authoritative.
        sendToRNode(Data([0xC0, 0x07, 0xFF, 0xC0]))
        sendToRNode(Data([0xC0, 0x06, 0xFF, 0xC0]))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard self.connectedDeviceID != nil else {
                completion(
                    .failure(RNodeRadioConfigurationError.rnodeNotConnected)
                )
                return
            }

            if self.radioReady {
                self.setRadioConnectionMessage("RNode data channel ready")
                print("RNode radio configuration verified: radio is ON")
                completion(.success(configuration))
                return
            }

            if retryCount == 0, self.radioLocked != true {
                print("RNode radio stayed off; retrying startup once")
                self.radioErrorMessage = nil
                self.sendToRNode(Data([0xC0, 0x06, 0x01, 0xC0]))
                self.verifyRadioStarted(
                    configuration: configuration,
                    retryCount: 1,
                    completion: completion
                )
                return
            }

            let error: RNodeRadioConfigurationError
            if self.radioLocked == true {
                error = .radioLocked
            } else {
                error = .radioDidNotStart(self.radioErrorMessage)
            }
            self.radioReady = false
            self.setRadioConnectionMessage(error.localizedDescription)
            completion(.failure(error))
        }
    }

    private static func bigEndianBytes(
        _ value: UInt32
    ) -> [UInt8] {
        [
            UInt8(
                (value >> 24) & 0xFF
            ),
            UInt8(
                (value >> 16) & 0xFF
            ),
            UInt8(
                (value >> 8) & 0xFF
            ),
            UInt8(
                value & 0xFF
            )
        ]
    }
}
