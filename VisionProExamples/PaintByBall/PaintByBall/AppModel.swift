//
//  AppModel.swift
//  PaintByBall
//
//  Created by Fabio Dela Antonio on 16/09/2024.
//

import SwiftUI
import RealityKit
import ARKit
import MixedRealityCapture
import OSLog

@MainActor
let logger = Logger(subsystem: "PaintByBallApp", category: "general")

@Observable
@MainActor
final class AppModel {
    let session = ARKitSession()
    let handTracking = HandTrackingProvider()
    let worldTracking = WorldTrackingProvider()
    let imageTracking = MixedRealityImageTracking.imageTrackingProvider()

    private(set) var mixedRealityEntity = Entity()
    private(set) var contentEntity = Entity()
    private(set) var canvas: CanvasEntity?

    var errorState = false

    let initialTime: CFTimeInterval

    private var lastShotTime: TimeInterval?
    private var didShoot = false

    var ballRadius: Float = 0.01
    var hue: Float = 0.5
    var saturation: Float = 0.8
    var brightness: Float = 0.8

    var ballColor: UIColor {
        UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1.0)
    }

    var dataProvidersAreSupported: Bool {
        HandTrackingProvider.isSupported && WorldTrackingProvider.isSupported && ImageTrackingProvider.isSupported
    }

    var isReadyToRun: Bool {
        handTracking.state == .initialized && worldTracking.state == .initialized && imageTracking.state == .initialized
    }

    private let mrcManager: MixedRealityCaptureManager
    private(set) var externalCameraEntity = Entity()

    init() {
        self.initialTime = CACurrentMediaTime()

        self.mrcManager = MixedRealityCaptureManager()
        mrcManager.delegate = self
    }

    func setupContentEntity(attachments: RealityViewAttachments) -> Entity {
        if let canvas = CanvasEntity(backgroundColor: .init(gray: 1, alpha: 1)) {
            mixedRealityEntity.addChild(canvas)

            let referenceEntity = Entity()
            referenceEntity.addChild(mixedRealityEntity)
            mrcManager.referenceEntity = referenceEntity

            contentEntity.addChild(referenceEntity)
            self.canvas = canvas
        }

        if let panelAttachment = attachments.entity(for: "panel") {
            panelAttachment.position = CanvasConstants.canvasPosition + Vector3(0, -CanvasConstants.canvasHeight * 0.5 - 0.15, 0)
            panelAttachment.transform.rotation = .init(angle: -.pi/6.0, axis: Vector3(1, 0, 0))
            contentEntity.addChild(panelAttachment)
        }

        externalCameraEntity.position = Vector3(-1.5, 1.5, 0)
        externalCameraEntity.addChild(MixedRealityCapture.EntityBuilder.makeGizmo())
        contentEntity.addChild(externalCameraEntity)

        contentEntity.transform.translation = .zero
        return contentEntity
    }

    func clear() {
        canvas?.clear(with: ballColor)
    }

    func quit() {
        exit(0)
    }

    func processImageTrackingUpdates() async {
        for await update in imageTracking.anchorUpdates {
            mrcManager.updateCameraPosition(with: update.anchor)
        }
    }

    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor

            guard handAnchor.chirality == .right,
                  handAnchor.isTracked,
                  let indexFingerKnuckle = handAnchor.handSkeleton?.joint(.indexFingerKnuckle),
                  let thumbTip = handAnchor.handSkeleton?.joint(.thumbTip),
                  let indexFingerIntermediateTip = handAnchor.handSkeleton?.joint(.indexFingerIntermediateTip),
                  let indexFingerTip = handAnchor.handSkeleton?.joint(.indexFingerTip)
            else {
                continue
            }

            let elapsedTime = CACurrentMediaTime() - initialTime

            let indexFingerKnucklePosition = (handAnchor.originFromAnchorTransform * indexFingerKnuckle.anchorFromJointTransform).columns.3
            let thumbTipPosition = (handAnchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform).columns.3

            let distance = (indexFingerKnucklePosition.xyz - thumbTipPosition.xyz).norm

            let indexFingerIntermediateTipPosition = (handAnchor.originFromAnchorTransform * indexFingerIntermediateTip.anchorFromJointTransform).columns.3
            let indexFingerTipPosition = (handAnchor.originFromAnchorTransform * indexFingerTip.anchorFromJointTransform).columns.3

            let shotDirection = (indexFingerTipPosition.xyz - indexFingerIntermediateTipPosition.xyz).normalized
            let initialPosition = indexFingerTipPosition.xyz

            if distance <= 0.04 {

                func shoot() {
                    lastShotTime = elapsedTime
                    didShoot = true

                    let results = contentEntity.scene?.raycast(from: initialPosition, to: initialPosition + (shotDirection * 10.0)) ?? []

                    for result in results {
                        if let _ = result.entity as? CanvasEntity {
                            let color = ballColor
                            let radius = ballRadius

                            Shooter.shootBullet(
                                position: initialPosition + (shotDirection * radius),
                                finalPosition: result.position,
                                addTo: mixedRealityEntity,
                                withRadius: radius,
                                color: color,
                                completion: { [weak self] in
                                    self?.canvas?.draw(
                                        collisionPoint: result.position,
                                        color: color,
                                        radius: radius
                                    )
                                }
                            )
                        }
                    }
                }

                if !didShoot {
                    if let lastShotTime {
                        if (elapsedTime - lastShotTime) > 0.25 {
                            shoot()
                        }
                    } else {
                        shoot()
                    }
                }
            } else {
                didShoot = false
            }
        }
    }

    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(type: _, status: let status):
                logger.info("Authorization changed to: \(status)")

                if status == .denied {
                    errorState = true
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                logger.info("Data provider changed: \(providers), \(state)")
                if let error {
                    logger.error("Data provider reached an error state: \(error)")
                    errorState = true
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }
}

extension AppModel: MixedRealityCaptureDelegate {

    func didUpdateCamera(pose: Pose) {
        externalCameraEntity.transform = Transform(
            scale: .init(1, 1, 1),
            rotation: pose.rotation,
            translation: pose.position
        )
    }
}
