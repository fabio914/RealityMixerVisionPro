//
//  AppViewModel.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import SwiftUI
import ARKit
import RealityKit
import OSLog

let logger = Logger(subsystem: "RealityMixerExample", category: "general")

enum AppViewModelError: Error {
    case providerNotSupported
}

@Observable
@MainActor
final class AppViewModel {
    let session = ARKitSession()
    let handTracking = HandTrackingProvider()
    let worldTraking = WorldTrackingProvider()

    let imageTracking = ImageTrackingProvider(
        referenceImages: ReferenceImage.loadReferenceImages(inGroupNamed: "AR Resources")
    )

    private(set) var particlesEntity = Entity()
    private(set) var externalCameraEntity = Entity()
    private(set) var contentEntity = Entity()

    private let forcesContainer = ForcesContainerComponent(forces: [
        "drag": DragForce(),
        "gravity": GravityForce()
    ])

    var dataProvidersAreSupported: Bool {
        HandTrackingProvider.isSupported && ImageTrackingProvider.isSupported && WorldTrackingProvider.isSupported
    }

    var isReadyToRun: Bool {
        handTracking.state == .initialized && imageTracking.state == .initialized && worldTraking.state == .initialized
    }

    private(set) var hasError: Bool = false

    private let mrcManager: MixedRealityCaptureManager

    let particlesPosition = Vector3(0, 1.5, -1.0)

    init() {
        self.mrcManager = .init()
        mrcManager.delegate = self
    }

    func setupContentEntity(_ attachments: RealityViewAttachments) -> Entity {
        for _ in 0 ..< 100 {
            particlesEntity.addChild(EntityBuilder.buildParticle())
        }

        particlesEntity.addChild(EntityBuilder.buildBox())
        particlesEntity.position = particlesPosition

        let mixedRealityEntity = Entity()

        // We'll only render the particles and box in the Mixed Reality video
        mixedRealityEntity.addChild(particlesEntity)
        mrcManager.referenceEntity = mixedRealityEntity

        contentEntity.addChild(mixedRealityEntity)

        let forcesEntity = Entity()
        forcesEntity.components.set(forcesContainer)
        contentEntity.addChild(forcesEntity)

        externalCameraEntity.position = Vector3(0, 1.5, -2.0)
        externalCameraEntity.addChild(EntityBuilder.makeBase())
        contentEntity.addChild(externalCameraEntity)

        contentEntity.transform.translation = .zero
        return contentEntity
    }

    func runSession() async throws {
        if dataProvidersAreSupported && isReadyToRun {
            try await session.run([handTracking, imageTracking, worldTraking])
        } else {
            throw AppViewModelError.providerNotSupported
        }
    }

    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor

            guard handAnchor.isTracked,
                  let indexFingerTip = handAnchor.handSkeleton?.joint(.indexFingerTip),
                  let thumbTip = handAnchor.handSkeleton?.joint(.thumbTip)
            else {
                continue
            }

            let indexFingerTipPosition = (handAnchor.originFromAnchorTransform * indexFingerTip.anchorFromJointTransform).columns.3
            let thumbTipPosition = (handAnchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform).columns.3

            let distance = (indexFingerTipPosition.xyz - thumbTipPosition.xyz).norm
            let midPoint = (indexFingerTipPosition.xyz + thumbTipPosition.xyz) * 0.5

            let key = switch handAnchor.chirality {
            case .right:
                "right-hand"
            case .left:
                "left-hand"
            }

            if distance < 0.01 {
                let pointInParticlesCoordinates = midPoint - particlesPosition
                forcesContainer.forces[key] = AttractionForce(position: pointInParticlesCoordinates)
            } else {
                forcesContainer.forces.removeValue(forKey: key)
            }
        }
    }

    func processImageTrackingUpdates() async {
        for await update in imageTracking.anchorUpdates {
            let imageAnchor = update.anchor
            mrcManager.updateCameraPosition(with: imageAnchor)
        }
    }

    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(type: _, status: let status):
                logger.info("Authorization changed to: \(status)")

                if status == .denied {
                    hasError = true
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                logger.info("Data provider changed: \(providers), \(state)")
                if let error {
                    logger.error("Data provider reached an error state: \(error)")
                    hasError = true
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }
}

extension AppViewModel: @preconcurrency MixedRealityCaptureDelegate {

    func didUpdateCamera(pose: Pose) {
        externalCameraEntity.transform = Transform(
            scale: .init(1, 1, 1),
            rotation: pose.rotation,
            translation: pose.position
        )
    }
}
