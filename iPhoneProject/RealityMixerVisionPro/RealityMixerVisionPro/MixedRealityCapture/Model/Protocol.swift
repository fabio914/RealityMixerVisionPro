//
//  Protocol.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation

enum MRCProtocol {
    static let protocolIdentifier: UInt32 = 13371337
}

enum PayloadType: UInt32, RawRepresentable {
    case cameraUpdate = 1
    case buttonPress = 2
    case videoData = 11
}
