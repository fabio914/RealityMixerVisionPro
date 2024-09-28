//
//  VideoEncoder.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import VideoToolbox

final class VideoEncoder {
    let size: CGSize
    private var compressionSession: VTCompressionSession
    private var pixelBuffer: CVPixelBuffer
    private var finalized = false

    private let width: Int
    private let height: Int

    public init?(
        size: CGSize,
        frameRate: Int,
        bitRate: Int
    ) {
        self.size = size
        var session: VTCompressionSession?

        VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(size.width),
            height: Int32(size.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard let session = session else {
            return nil
        }

        var err: OSStatus = noErr

        err = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)

        if err != noErr {
            logger.warning("VTSessionSetProperty(kVTCompressionPropertyKey_ProfileLevel) failed (\(err))")
        }

        err = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        if noErr != err {
            logger.warning("VTSessionSetProperty(kVTCompressionPropertyKey_RealTime) failed (\(err))")
        }

        err = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
        if noErr != err {
            logger.warning("VTSessionSetProperty(kVTCompressionPropertyKey_AverageBitRate) failed (\(err))")
        }

        let byteLimit = (Double(bitRate) / 8 * 1.5) as CFNumber
        let secLimit = Double(1.0) as CFNumber
        let limitsArray = [ byteLimit, secLimit ] as CFArray
        err = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limitsArray)
        if noErr != err {
            logger.warning("Warning: VTSessionSetProperty(kVTCompressionPropertyKey_DataRateLimits) failed (\(err))")
        }

        var pixelBuffer: CVPixelBuffer?
        let pixelFormat = kCVPixelFormatType_32BGRA

        self.width = Int(size.width)
        self.height = Int(size.height)

        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard let pixelBuffer else {
            return nil
        }

        self.compressionSession = session
        self.pixelBuffer = pixelBuffer
    }

    func didEncodeFrame(frame: CMSampleBuffer) -> Data {

        //----AVCC to Elem stream-----//
        let elementaryStream = NSMutableData()

        //1. check if CMBuffer had I-frame
        var isIFrame:Bool = false
        let attachmentsArray:CFArray = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: false)!
        //check how many attachments
        if ( CFArrayGetCount(attachmentsArray) > 0 ) {
            let dict = CFArrayGetValueAtIndex(attachmentsArray, 0)
            let dictRef: CFDictionary = unsafeBitCast(dict, to: CFDictionary.self)
            //get value
            let value = CFDictionaryGetValue(dictRef, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
            if ( value != nil ){
                print ("IFrame found...")
                isIFrame = true
            }
        }

        //2. define the start code
        let nStartCodeLength:size_t = 4
        let nStartCode:[UInt8] = [0x00, 0x00, 0x00, 0x01]

        //3. write the SPS and PPS before I-frame
        if ( isIFrame == true ){
            let description: CMFormatDescription = CMSampleBufferGetFormatDescription(frame)!
            //how many params
            var numParams: size_t = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &numParams, nalUnitHeaderLengthOut: nil)

            //write each param-set to elementary stream
            for i in 0..<numParams {
                var parameterSetPointer: UnsafePointer<UInt8>?
                var parameterSetLength: Int = 0

                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    description,
                    parameterSetIndex: i,
                    parameterSetPointerOut: &parameterSetPointer,
                    parameterSetSizeOut: &parameterSetLength,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )

                elementaryStream.append(nStartCode, length: nStartCodeLength)
                elementaryStream.append(parameterSetPointer!, length: parameterSetLength)
            }
        }

        //4. Get a pointer to the raw AVCC NAL unit data in the sample buffer
        var blockBufferLength: Int = 0
        var bufferDataPointer: UnsafeMutablePointer<Int8>?

        CMBlockBufferGetDataPointer(
            CMSampleBufferGetDataBuffer(frame)!,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &blockBufferLength,
            dataPointerOut: &bufferDataPointer
        )

        print ("Block length = ", blockBufferLength)

        //5. Loop through all the NAL units in the block buffer
        var bufferOffset:size_t = 0
        let AVCCHeaderLength: Int = 4
        while (bufferOffset < (blockBufferLength - AVCCHeaderLength) ) {
            // Read the NAL unit length
            var NALUnitLength:UInt32 =  0
            memcpy(&NALUnitLength, bufferDataPointer! + bufferOffset, AVCCHeaderLength)
            //Big-Endian to Little-Endian
            NALUnitLength = CFSwapInt32(NALUnitLength)
            if ( NALUnitLength > 0 ){
                print ( "NALUnitLen = ", NALUnitLength)
                // Write start code to the elementary stream
                elementaryStream.append(nStartCode, length: nStartCodeLength)
                // Write the NAL unit without the AVCC length header to the elementary stream
                elementaryStream.append(bufferDataPointer! + bufferOffset + AVCCHeaderLength, length: Int(NALUnitLength))
                // Move to the next NAL unit in the block buffer
                bufferOffset += AVCCHeaderLength + size_t(NALUnitLength);
            }
        }

        return Data(elementaryStream)
    }

     func encodeFrame(
        _ frame: MTLTexture,
        presentationTime: Double,
        duration: Double,
        completedFrame: @escaping (_ encodedFrame: Data) -> Void
     ) {
         guard !finalized else {
             return
         }

         CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

         guard let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
         }

         let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
         let region = MTLRegionMake2D(0, 0, self.width, self.height)

         // Assuming the size of the frame is correct!

         // FIXME: We shouldn't modify this CVPixelBuffer while a `VTCompressionSessionEncodeFrame`
         // operation is still running...
         frame.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

         CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

         let presentationCMTime = CMTime(value: Int64(presentationTime * 1000), timescale: 1000)
         let durationCMTime = CMTime(value: Int64(duration * 1000), timescale: 1000)

         VTCompressionSessionEncodeFrame(
             compressionSession,
             imageBuffer: pixelBuffer,
             presentationTimeStamp: presentationCMTime,
             duration: durationCMTime,
             frameProperties: nil,
             infoFlagsOut: nil,
             outputHandler: { [weak self] status, infoFlags, sampleBuffer in
                 guard let self = self,
                     let sampleBuffer = sampleBuffer
                 else { return }

                 let result = self.didEncodeFrame(frame: sampleBuffer)
                 completedFrame(result)
             }
         )
     }

     func finalize() {
         guard !finalized else { return }
         finalized = true

         // Consider finishing remaining frames
         VTCompressionSessionInvalidate(compressionSession)
     }
}
