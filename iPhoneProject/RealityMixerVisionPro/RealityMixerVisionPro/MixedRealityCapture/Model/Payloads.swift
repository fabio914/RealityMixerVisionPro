//
//  Payloads.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import ARKit

private let protocolIdentifier: UInt32 = 13371337

enum PayloadType: UInt32, RawRepresentable {
    case cameraUpdate = 1
    case buttonPress = 2
}

struct CameraUpdatePayload {
    // Header
    let magic = protocolIdentifier
    let payloadType: UInt32 = PayloadType.cameraUpdate.rawValue
    let payloadLength = UInt32(8 * MemoryLayout<Float32>.size + 2 * MemoryLayout<UInt32>.size)

    // Payload
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

    init?(frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else { return nil }

        let projection = frame.camera.projectionMatrix
        let yScale = projection[1,1]
        let yFov = 2.0 * atan(1/yScale)

        let imageResolution = frame.camera.imageResolution
        let radiansToDegrees = 180.0/Float.pi

        let position = frame.camera.transform.columns.3

        let positionVector = Vector3(
            x: position.x,
            y: position.y,
            z: position.z
        )

        let rotation = Quaternion(rotationMatrix: SCNMatrix4(frame.camera.transform))
        let pose = Pose(position: positionVector, rotation: rotation)

        self.init(
            pose: pose,
            size: imageResolution,
            verticalFOV: yFov * radiansToDegrees
        )
    }

    init(
        pose: Pose,
        size: CGSize,
        verticalFOV: Float
    ) {
        self.px = Float32(pose.position.x)
        self.py = Float32(pose.position.y)
        self.pz = Float32(pose.position.z)
        self.qx = Float32(pose.rotation.x)
        self.qy = Float32(pose.rotation.y)
        self.qz = Float32(pose.rotation.z)
        self.qw = Float32(pose.rotation.w)

        self.cameraWidth = UInt32(size.width)
        self.cameraHeight = UInt32(size.height)
        self.cameraVerticalFOV = Float32(verticalFOV)
    }

    var data: Data {
        let length = MemoryLayout<CameraUpdatePayload>.size
        var copy = self
        let data = Data(bytes: &copy, count: length)
        return data
    }
}

struct ButtonPressPayload {
    // Header
    let magic = protocolIdentifier
    let payloadType: UInt32 = PayloadType.buttonPress.rawValue
    let payloadLength: UInt32 = UInt32(MemoryLayout<UInt8>.size)

    // Payload
    let buttonAscii: UInt8

    init(buttonAscii: UInt8) {
        self.buttonAscii = buttonAscii
    }

    var data: Data {
        let length = MemoryLayout<ButtonPressPayload>.size
        var copy = self
        let data = Data(bytes: &copy, count: length)
        return data
    }
}
