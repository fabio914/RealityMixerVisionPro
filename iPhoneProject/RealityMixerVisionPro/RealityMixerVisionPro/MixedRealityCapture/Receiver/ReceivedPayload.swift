//
//  ReceivedPayload.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation

enum ReceivedPayload {
    case videoData(Data)

    init?(from frame: ReceivedFrame) {
        guard let payloadType = PayloadType(rawValue: frame.payloadType) else { return nil }

        switch payloadType {
        case .videoData:
            self = .videoData(frame.data)
        default:
            return nil
        }
    }
}
