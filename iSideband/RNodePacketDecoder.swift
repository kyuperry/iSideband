//
//  RNodePacketDecoder.swift
//  iSideband
//

import Foundation

final class RNodePacketDecoder {

    func decode(_ data: Data) -> RNodePacket {
        RNodePacket(raw: data)
    }
}
