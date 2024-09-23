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
    var worldTraking: WorldTrackingProvider { get }
    func didUpdateCamera(pose: Pose)
}

final class MixedRealityCaptureManager {
    var delegate: MixedRealityCaptureDelegate?

    private let server: MixedRealityServer

    private var displayLink: CADisplayLink?

    // Camera Tracking
    private var cameraExtrinsic: Pose?
    private(set) var imageAnchorToWorld: Pose?
    private(set) var cameraToWorld: Pose?

    // Device Tracking
    private(set) var devicePose: Pose?

    // Mixed Reality Rendering
    private var encoder: VideoEncoder?
    private var renderer: MixedRealityRenderer?

    // The Mixed Reality video will be rendered with
    // all the children of this entity.
    var referenceEntity: Entity?

    let framesPerSecond: Double = 30.0

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
        displayLink.preferredFramesPerSecond = Int(framesPerSecond)
        displayLink.add(to: .main, forMode: .default)
        self.displayLink = displayLink
    }

    @MainActor
    @objc private func update(with sender: CADisplayLink) {
        server.update()

        if let deviceAnchor = delegate?.worldTraking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            self.devicePose = Pose(deviceAnchor.originFromAnchorTransform)
        }

        guard let encoder,
           let renderer,
           let cameraInWorldCoordinates,
           let referenceEntity,
           let devicePose
        else {
            return
        }

        let cameraTransform = Transform(
            scale: .init(x: 1, y: 1, z: 1),
            rotation: cameraInWorldCoordinates.rotation,
            translation: cameraInWorldCoordinates.position
        )

        do {
            let frame = try renderer.render(
                referenceEntity: referenceEntity,
                cameraTransform: cameraTransform,
                devicePosition: devicePose.position
            )

            let presentationTime = 0.0
            let frameDuration = 1.0/framesPerSecond

            encoder.encodeFrame(frame, presentationTime: presentationTime, duration: frameDuration) { [weak self] data in
                self?.server.send(data: VideoDataPayload.makePayload(encodedVideoData: data))
            }
        } catch {
            logger.error("Failed to render frame: \(error)")
        }
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

    deinit {
        encoder?.finalize()
    }
}

extension MixedRealityCaptureManager: @preconcurrency MixedRealityServerDelegate {

    func didReceiveButtonPress(_ button: UInt8) {

    }

    @MainActor
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

        if encoder == nil {
            self.encoder = VideoEncoder(
                size: .init(width: imageSize.width * 2, height: imageSize.height * 2)
            )
        }

        if renderer == nil {
            do {
                self.renderer = try MixedRealityRenderer(
                    cameraIntrinsic: .init(imageSize: imageSize, verticalFOV: verticalFOV)
                )
            } catch {
                logger.error("Failed to instantiate renderer: \(error)")
                self.renderer = nil
            }
        }
    }
}
