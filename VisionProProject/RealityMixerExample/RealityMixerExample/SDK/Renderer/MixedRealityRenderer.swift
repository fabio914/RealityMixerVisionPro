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
    case unableToInstantiateComputePipeline
    case unableToInstantiateRealityRenderer(Error)
    case unableToInstantiateCommandBuffer
    case unableToMakeEvent
    case unableToInstantiateBlitEncoder
    case unableToInstantiateComputeEncoder
    case unableToInstantiateCVPixelBuffer
}

final class MixedRealityRenderer {

    let cameraIntrinsic: CameraIntrinsic

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    let foregroundTexture: MTLTexture
    let backgroundTexture: MTLTexture
    let foregroundAlphaTexture: MTLTexture
    let backgroundAlphaTexture: MTLTexture
    let streamingTexture: MTLTexture

    let computePipelineState: MTLComputePipelineState

    private let parentEntity = Entity()
    private let camera = PerspectiveCamera()
    private let cameraNear: Float = 0.01
    private let cameraFar: Float = 100.0

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

        guard let foregroundTexture = device.makeTexture(descriptor: textureDescriptor),
            let backgroundTexture = device.makeTexture(descriptor: textureDescriptor),
            let foregroundAlphaTexture = device.makeTexture(descriptor: textureDescriptor),
            let backgroundAlphaTexture = device.makeTexture(descriptor: textureDescriptor)
        else {
            throw MixedRealityRendererError.unableToInstantiateTexture
        }

        let streamingTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 2 * Int(cameraIntrinsic.imageSize.width),
            height: 2 * Int(cameraIntrinsic.imageSize.height),
            mipmapped: false
        )

        streamingTextureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let streamingTexture = device.makeTexture(descriptor: streamingTextureDescriptor) else {
            throw MixedRealityRendererError.unableToInstantiateTexture
        }

        self.foregroundTexture = foregroundTexture
        self.backgroundTexture = backgroundTexture
        self.foregroundAlphaTexture = foregroundAlphaTexture
        self.backgroundAlphaTexture = backgroundAlphaTexture
        self.streamingTexture = streamingTexture

        // Compute Pipeline for the Alpha Extractor shader
        guard let defaultLibrary = device.makeDefaultLibrary(),
            let kernelFunction = defaultLibrary.makeFunction(name: "textureProcessingKernel"),
            let computePipelineState = try? device.makeComputePipelineState(function: kernelFunction)
        else {
            throw MixedRealityRendererError.unableToInstantiateComputePipeline
        }

        self.computePipelineState = computePipelineState

        camera.camera.fieldOfViewInDegrees = cameraIntrinsic.verticalFOV

        do {
            let realityRenderer = try RealityKit.RealityRenderer()
            realityRenderer.cameraSettings.colorBackground = .color(.init(gray: 0.0, alpha: 0.0))

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

        let cameraForward = cameraTransform.matrix.forwardVector
        let cameraPosition = cameraTransform.translation

        let distance = -1.0 * (cameraForward.dot(devicePosition - cameraPosition))
        let projectedDistance = min(max(cameraNear, distance), cameraFar)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw MixedRealityRendererError.unableToInstantiateCommandBuffer
        }

        // Rendering Foreground Texture
        camera.camera.near = cameraNear
        camera.camera.far = projectedDistance

        guard let event = device.makeEvent() else {
            throw MixedRealityRendererError.unableToMakeEvent
        }

        do {
            let descriptor = RealityKit.RealityRenderer.CameraOutput.Descriptor.singleProjection(
                colorTexture: foregroundTexture
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

        blitEncoder.copy(
            from: foregroundTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(
                width: foregroundTexture.width,
                height: foregroundTexture.height,
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

        // Rendering Background Texture
        camera.camera.near = projectedDistance
        camera.camera.far = cameraFar

        guard let backgroundCommandBuffer = commandQueue.makeCommandBuffer() else {
            throw MixedRealityRendererError.unableToInstantiateCommandBuffer
        }

        guard let backgroundEvent = device.makeEvent() else {
            throw MixedRealityRendererError.unableToMakeEvent
        }

        do {
            let descriptor = RealityKit.RealityRenderer.CameraOutput.Descriptor.singleProjection(
                colorTexture: backgroundTexture
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
                    .signal(backgroundEvent, value: 1)
                ]
            )
        } catch {
            print("Error: \(error)")
        }

        backgroundCommandBuffer.encodeWaitForEvent(backgroundEvent, value: 1)

        guard let backgroundBlitEncoder = backgroundCommandBuffer.makeBlitCommandEncoder() else {
            throw MixedRealityRendererError.unableToInstantiateBlitEncoder
        }

        backgroundBlitEncoder.copy(
            from: backgroundTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(
                width: backgroundTexture.width,
                height: backgroundTexture.height,
                depth: 1
            ),
            to: streamingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: foregroundTexture.width, y: 0, z: 0)
        )

        backgroundBlitEncoder.endEncoding()

        backgroundCommandBuffer.commit()
        backgroundCommandBuffer.waitUntilCompleted()

        // Extract Alpha from Foreground Texture
        guard let alphaExtractionCommandBuffer = commandQueue.makeCommandBuffer() else {
            throw MixedRealityRendererError.unableToInstantiateCommandBuffer
        }

        try extractAlpha(
            commandBuffer: alphaExtractionCommandBuffer,
            inputTexture: foregroundTexture,
            outputTexture: foregroundAlphaTexture
        )

        guard let foregroundAlphaBlitEncoder = alphaExtractionCommandBuffer.makeBlitCommandEncoder() else {
            throw MixedRealityRendererError.unableToInstantiateBlitEncoder
        }

        foregroundAlphaBlitEncoder.copy(
            from: foregroundAlphaTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(
                width: foregroundAlphaTexture.width,
                height: foregroundAlphaTexture.height,
                depth: 1
            ),
            to: streamingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: foregroundTexture.height, z: 0)
        )

        foregroundAlphaBlitEncoder.endEncoding()

        alphaExtractionCommandBuffer.commit()
        alphaExtractionCommandBuffer.waitUntilCompleted()

        // Extract Alpha from Background Texture
        guard let alphaBackgroundExtractionCommandBuffer = commandQueue.makeCommandBuffer() else {
            throw MixedRealityRendererError.unableToInstantiateCommandBuffer
        }

        try extractAlpha(
            commandBuffer: alphaBackgroundExtractionCommandBuffer,
            inputTexture: backgroundTexture,
            outputTexture: backgroundAlphaTexture
        )

        guard let backgroundAlphaBlitEncoder = alphaBackgroundExtractionCommandBuffer.makeBlitCommandEncoder() else {
            throw MixedRealityRendererError.unableToInstantiateBlitEncoder
        }

        backgroundAlphaBlitEncoder.copy(
            from: backgroundAlphaTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(
                width: backgroundAlphaTexture.width,
                height: backgroundAlphaTexture.height,
                depth: 1
            ),
            to: streamingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: foregroundTexture.width, y: backgroundTexture.height, z: 0)
        )

        backgroundAlphaBlitEncoder.endEncoding()

        alphaBackgroundExtractionCommandBuffer.commit()
        alphaBackgroundExtractionCommandBuffer.waitUntilCompleted()

        guard let cvPixelBuffer = streamingTexture.cvPixelBuffer else {
            throw MixedRealityRendererError.unableToInstantiateCVPixelBuffer
        }

        return cvPixelBuffer
    }

    private func extractAlpha(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture
    ) throws {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MixedRealityRendererError.unableToInstantiateComputeEncoder
        }

        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (inputTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (inputTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
    }
}
