//
//  CameraUpdateSender.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import SwiftSocket
import ARKit

protocol CameraUpdateSenderProtocol: AnyObject {
    func sendCameraUpdate(_ cameraUpdate: CameraUpdatePayload)
}

final class CameraUpdateSender: CameraUpdateSenderProtocol {
    let client: TCPClient

    init(client: TCPClient) {
        self.client = client
    }

    func sendCameraUpdate(_ cameraUpdate: CameraUpdatePayload) {
        _ = client.send(data: cameraUpdate.data)
    }

    deinit {
        client.close()
    }
}
