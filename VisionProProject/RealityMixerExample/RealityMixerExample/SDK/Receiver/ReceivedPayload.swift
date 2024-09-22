//
//  ReceivedPayload.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation

enum ReceivedPayload {

    struct CameraUpdate {
        let px: Float32
        let py: Float32
        let pz: Float32
        let qx: Float32
        let qy: Float32
        let qz: Float32
        let qw: Float32

        let cameraWidth: UInt32
        let cameraHeight: UInt32
        let cameraVerticalFOV: Float32
    }

    case cameraUpdate(Pose, CGSize, _ verticalFOV: Float)
    case buttonPress(UInt8)

    init?(from frame: ReceivedFrame) {
        guard let payloadType = PayloadType(rawValue: frame.payloadType) else { return nil }

        switch payloadType {
        case .cameraUpdate:
            guard frame.data.count == MemoryLayout<CameraUpdate>.size else { return nil }
            let cameraUpdate = frame.data.withUnsafeBytes({ $0.load(as: CameraUpdate.self) })
            let pose = Pose(
                position: .init(x: cameraUpdate.px, y: cameraUpdate.py, z: cameraUpdate.pz),
                rotation: .init(x: cameraUpdate.qx, y: cameraUpdate.qy, z: cameraUpdate.qz, w: cameraUpdate.qw)
            )
            let imageSize = CGSize(
                width: Int(cameraUpdate.cameraWidth),
                height: Int(cameraUpdate.cameraHeight)
            )
            let verticalFOV = Float(cameraUpdate.cameraVerticalFOV)
            self = .cameraUpdate(pose, imageSize, verticalFOV)
        case .buttonPress:
            guard frame.data.count == MemoryLayout<UInt8>.size else { return nil }
            self = .buttonPress([UInt8](frame.data)[0])
        default:
            return nil
        }
    }
}
