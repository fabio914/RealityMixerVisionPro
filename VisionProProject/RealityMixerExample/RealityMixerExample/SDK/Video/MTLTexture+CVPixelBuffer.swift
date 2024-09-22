//
//  MTLTexture+CVPixelBuffer.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Metal
import AVFoundation
//import Accelerate

extension MTLTexture {

    var cvPixelBuffer: CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let pixelFormat = kCVPixelFormatType_32BGRA

        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            self.width,
            self.height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, self.width, self.height)

        self.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

//        var sourceBuffer = vImage_Buffer(
//            data: pixelBufferBytes,
//            height: vImagePixelCount(height),
//            width: vImagePixelCount(width),
//            rowBytes: bytesPerRow
//        )
//
//        var destinationBuffer = sourceBuffer
//        vImageVerticalReflect_ARGB8888(&sourceBuffer, &destinationBuffer, vImage_Flags(kvImageNoFlags))

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }
}
