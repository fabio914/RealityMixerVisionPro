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
    private var finalized = false

    public init?(size: CGSize) {
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

        self.compressionSession = session
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
        _ frame: CVImageBuffer,
        presentationTime: Double,
        duration: Double,
        completedFrame: @escaping (_ encodedFrame: Data) -> Void
     ) {
         guard !finalized else { return }

         let presentationCMTime = CMTime(value: Int64(presentationTime * 1000), timescale: 1000)
         let durationCMTime = CMTime(value: Int64(duration * 1000), timescale: 1000)

         VTCompressionSessionEncodeFrame(
             compressionSession,
             imageBuffer: frame,
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
