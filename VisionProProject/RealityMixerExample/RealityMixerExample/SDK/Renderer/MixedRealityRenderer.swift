//
//  MixedRealityRenderer.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import RealityKit
import AVFoundation

enum MixedRealityRendererError: Error {
    case unableToInstantiateMetalDevice
    case unableToInstantiateCommandQueue
    case unableToInstantiateTexture
    case unableToInstantiateRealityRenderer(Error)
    case unableToInstantiateCommandBuffer
    case unableToMakeEvent
    case unableToInstantiateBlitEncoder
    case unableToInstantiateCVPixelBuffer
}

final class MixedRealityRenderer {

    let cameraIntrinsic: CameraIntrinsic

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    let renderingTexture: MTLTexture
    let streamingTexture: MTLTexture

    private let parentEntity = Entity()
    private let camera = PerspectiveCamera()

    private let realityRenderer: RealityRenderer

    @MainActor
    init(cameraIntrinsic: CameraIntrinsic) throws {
        self.cameraIntrinsic = cameraIntrinsic

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MixedRealityRendererError.unableToInstantiateMetalDevice
        }

        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw MixedRealityRendererError.unableToInstantiateCommandQueue
        }

        self.commandQueue = commandQueue

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(cameraIntrinsic.imageSize.width),
            height: Int(cameraIntrinsic.imageSize.height),
            mipmapped: false
        )

        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let renderingTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw MixedRealityRendererError.unableToInstantiateTexture
        }

        let streamingTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 2 * Int(cameraIntrinsic.imageSize.width),
            height: Int(cameraIntrinsic.imageSize.height),
            mipmapped: false
        )

        streamingTextureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let streamingTexture = device.makeTexture(descriptor: streamingTextureDescriptor) else {
            throw MixedRealityRendererError.unableToInstantiateTexture
        }


        self.renderingTexture = renderingTexture
        self.streamingTexture = streamingTexture

        camera.camera.fieldOfViewInDegrees = cameraIntrinsic.verticalFOV

        do {
            let realityRenderer = try RealityKit.RealityRenderer()
            realityRenderer.cameraSettings.colorBackground = .color(.init(gray: 0.0, alpha: 1.0))

            realityRenderer.entities.append(parentEntity)

            realityRenderer.entities.append(camera)
            realityRenderer.activeCamera = camera
            realityRenderer.lighting.intensityExponent = 13.0

            self.realityRenderer = realityRenderer
        } catch {
            throw MixedRealityRendererError.unableToInstantiateRealityRenderer(error)
        }
    }

    @MainActor
    func render(
        referenceEntity: Entity,
        cameraTransform: Transform,
        devicePosition: Vector3
    ) throws -> CVPixelBuffer {
        defer {
            let children = parentEntity.children
            children.forEach({ referenceEntity.addChild($0) })
        }

//        let clonedEntity = referenceEntity.clone(recursive: true)
        let children = referenceEntity.children

        parentEntity.children.forEach({ $0.removeFromParent() })
        children.forEach({ parentEntity.addChild($0) })

        camera.transform = cameraTransform

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw MixedRealityRendererError.unableToInstantiateCommandBuffer
        }

        guard let event = device.makeEvent() else {
            throw MixedRealityRendererError.unableToMakeEvent
        }

        do {
            let descriptor = RealityKit.RealityRenderer.CameraOutput.Descriptor.singleProjection(
                colorTexture: renderingTexture
            )

            try realityRenderer.updateAndRender(
                deltaTime: 0.0,
                cameraOutput: .init(descriptor),
                whenScheduled: { _ in
                },
                onComplete: { renderer in
                },
                actionsBeforeRender: [
                ],
                actionsAfterRender: [
                    .signal(event, value: 1)
                ]
            )
        } catch {
            print("Error: \(error)")
        }

        commandBuffer.encodeWaitForEvent(event, value: 1)

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw MixedRealityRendererError.unableToInstantiateBlitEncoder
        }

        // Blit offscreenTexture to streamingTexture
        blitEncoder.copy(
            from: renderingTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(
                width: renderingTexture.width,
                height: renderingTexture.height,
                depth: 1
            ),
            to: streamingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )

        blitEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let cvPixelBuffer = streamingTexture.cvPixelBuffer else {
            throw MixedRealityRendererError.unableToInstantiateCVPixelBuffer
        }

        return cvPixelBuffer
    }
}
