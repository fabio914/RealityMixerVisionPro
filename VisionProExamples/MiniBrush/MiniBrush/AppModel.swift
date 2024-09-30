//
//  AppModel.swift
//  MiniBrush
//
//  Created by Fabio Dela Antonio on 29/09/2024.
//

import SwiftUI
import RealityKit
import ARKit
import OSLog
import MixedRealityCapture

@MainActor
let logger = Logger(subsystem: "MiniBrushApp", category: "general")

@Observable
@MainActor
final class AppModel {
    let session = ARKitSession()
    let handTracking = HandTrackingProvider()
    let worldTracking = WorldTrackingProvider()
    let imageTracking = MixedRealityImageTracking.imageTrackingProvider()

    private(set) var mixedRealityEntity = Entity()
    private(set) var contentEntity = Entity()

    let brushState = BrushState()
    private var drawingDocument: DrawingDocument?

    var errorState = false

    var brushRadius: Float = 0.005 {
        didSet {
            updateParameters()
        }
    }

    var hue: Float = 0.5 {
        didSet {
            updateParameters()
        }
    }

    var saturation: Float = 0.8 {
        didSet {
            updateParameters()
        }
    }

    var brightness: Float = 0.8 {
        didSet {
            updateParameters()
        }
    }

    var brushColor: UIColor {
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
        self.mrcManager = MixedRealityCaptureManager()
        mrcManager.delegate = self
    }

    func setupContentEntity(attachments: RealityViewAttachments) async -> Entity {
        let drawingDocument = await DrawingDocument(brushState: brushState)
        self.drawingDocument = drawingDocument
        self.updateParameters()

        mixedRealityEntity.addChild(drawingDocument.rootEntity)

        let referenceEntity = Entity()
        referenceEntity.addChild(mixedRealityEntity)
        mrcManager.referenceEntity = referenceEntity

        contentEntity.addChild(referenceEntity)

        if let panelAttachment = attachments.entity(for: "panel") {
            let attachmentPosition = Vector3(0, 1.0, -2.0)
            panelAttachment.position = attachmentPosition
            panelAttachment.transform.rotation = .init(angle: -.pi/6.0, axis: Vector3(1, 0, 0))
            contentEntity.addChild(panelAttachment)
        }

        externalCameraEntity.position = Vector3(-1.5, 1.5, 0)
        externalCameraEntity.addChild(MixedRealityCapture.EntityBuilder.makeGizmo())
        contentEntity.addChild(externalCameraEntity)

        contentEntity.transform.translation = .zero
        return contentEntity
    }

    private func updateParameters() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        brushColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        brushState.color = .init(Float(red), Float(green), Float(blue))
        brushState.radius = brushRadius
    }

    func clear() {
        drawingDocument?.clear()
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

            guard handAnchor.isTracked,
                handAnchor.chirality == .right, // Right hand only!
                let thumbTip = handAnchor.handSkeleton?.joint(.thumbTip),
                let indexFingerTip = handAnchor.handSkeleton?.joint(.indexFingerTip)
            else {
                continue
            }

            let indexFingerTipPosition = (handAnchor.originFromAnchorTransform * indexFingerTip.anchorFromJointTransform).columns.3
            let thumbTipPosition = (handAnchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform).columns.3

            let inputData = InputData(thumbTip: thumbTipPosition.xyz, indexFingerTip: indexFingerTipPosition.xyz)

            let chirality: Chirality = switch handAnchor.chirality {
            case .left:
                .left
            case .right:
                .right
            }

            drawingDocument?.receive(input: inputData, chirality: chirality)
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
