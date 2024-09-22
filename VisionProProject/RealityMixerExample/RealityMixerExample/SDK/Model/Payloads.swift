//
//  Payloads.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation

struct VideoDataPayload {
    // Header
    let magic = MRCProtocol.protocolIdentifier
    let payloadType: UInt32 = PayloadType.videoData.rawValue
    let payloadLength: UInt32

    var headerData: Data {
        let length = MemoryLayout<VideoDataPayload>.size
        var copy = self
        let data = Data(bytes: &copy, count: length)
        return data
    }

    static func makePayload(encodedVideoData: Data) -> Data {
        let header = Self.init(payloadLength: UInt32(encodedVideoData.count)).headerData
        return header + encodedVideoData
    }
}
