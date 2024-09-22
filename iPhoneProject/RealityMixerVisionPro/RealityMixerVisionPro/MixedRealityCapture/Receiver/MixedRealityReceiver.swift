//
//  MixedRealityReceiver.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import AVFoundation

protocol MixedRealityReceiverDelegate: AnyObject {
    func receiver(_ receiver: MixedRealityReceiver, didReceive pixelBuffer: CVPixelBuffer)
}

final class MixedRealityReceiver {
    weak var delegate: MixedRealityReceiverDelegate?
    private let frameCollection = FrameCollection()

    private lazy var decoder: VideoDecoder = {
        VideoDecoder(delegate: self)
    }()

    init(delegate: MixedRealityReceiverDelegate) {
        self.delegate = delegate
    }

    func add(data: Data) {
        frameCollection.add(data: data)
    }

    func update() {
        while let frame = frameCollection.next() {
            if let payload = ReceivedPayload(from: frame) {
                process(payload)
            }
        }
    }

    private func process(_ payload: ReceivedPayload) {
        switch payload {
        case .videoData(let data):
            decoder.process(data)
        }
    }
}

extension MixedRealityReceiver: DecoderDelegate {

    func didDecodeFrame(_ buffer: CVPixelBuffer) {
        delegate?.receiver(self, didReceive: buffer)
    }
}
