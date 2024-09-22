//
//  MixedRealityCaptureManager.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import SwiftUI
import ARKit
import RealityKit

protocol MixedRealityCaptureDelegate: AnyObject {
    func didUpdateCamera(pose: Pose)
}

final class MixedRealityCaptureManager {
    var delegate: MixedRealityCaptureDelegate?

    private let server: MixedRealityServer

    private var displayLink: CADisplayLink?

    private var cameraExtrinsic: Pose?
    private(set) var imageAnchorToWorld: Pose?
    private(set) var cameraToWorld: Pose?

    private var encoder: VideoEncoder?
    private var cameraIntrinsic: CameraIntrinsic?

    var cameraInWorldCoordinates: Pose? {
        guard let cameraExtrinsic, let cameraToWorld else { return nil }
        return cameraToWorld * cameraExtrinsic
    }

    init(delegate: MixedRealityCaptureDelegate? = nil) {
        self.delegate = delegate
        server = .init()
        server.delegate = self
        server.startServer()
        configureDisplayLink()
    }

    private func configureDisplayLink() {
        let displayLink = CADisplayLink(target: self, selector: #selector(update(with:)))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .default)
        self.displayLink = displayLink
    }

    @objc private func update(with sender: CADisplayLink) {
        server.update()

    }

    @MainActor
    func updateCameraPosition(with imageAnchor: ImageAnchor) {
        guard imageAnchor.isTracked else { return }
        let pose = Pose(imageAnchor.originFromAnchorTransform)
        self.imageAnchorToWorld = pose

        if let cameraExtrinsic {
            updateCameraToWorld(cameraPose: cameraExtrinsic, imageAnchorToWorld: pose)

            if let cameraInWorldCoordinates {
                delegate?.didUpdateCamera(pose: cameraInWorldCoordinates)
            }
        }
    }

    private func updateCameraToWorld(
        cameraPose: Pose,
        imageAnchorToWorld: Pose
    ) {
        let flipAnchor = Pose(
            position: .init(0, 0, 0),
            rotation: .init(angle: -.pi/2.0, axis: .init(x: 1, y: 0, z: 0))
        )

        let cameraToAnchor = cameraPose.inverse
        self.cameraToWorld = imageAnchorToWorld * flipAnchor * cameraToAnchor
    }
}

extension MixedRealityCaptureManager: MixedRealityServerDelegate {

    func didReceiveButtonPress(_ button: UInt8) {

    }

    func didReceiveCameraUpdate(
        _ pose: Pose,
        imageSize: CGSize,
        verticalFOV: Float
    ) {
        self.cameraExtrinsic = pose

        // If this is our first time setting the camera pose and we already
        // detected the image anchor:
        if cameraExtrinsic == nil, let imageAnchorToWorld {
            updateCameraToWorld(cameraPose: pose, imageAnchorToWorld: imageAnchorToWorld)
        }

        if let cameraInWorldCoordinates {
            delegate?.didUpdateCamera(pose: cameraInWorldCoordinates)
        }

        if cameraIntrinsic == nil {
            self.cameraIntrinsic = .init(imageSize: imageSize, verticalFOV: verticalFOV)
        }

        if encoder == nil {
            self.encoder = .init(size: imageSize)
        }
    }
}
