//
//  ReceivedFrame.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation

struct ReceivedFrame {
    static let protocolIdentifier: UInt32 = MRCProtocol.protocolIdentifier

    struct FrameHeader {
        let protocolIdentifier: UInt32
        let payloadType: UInt32
        let payloadLength: UInt32
    }

    let payloadType: UInt32
    let data: Data
    let length: Int

    init?(from data: Data) {
        let headerLength = MemoryLayout<FrameHeader>.size
        guard data.count >= headerLength else { return nil }

        let headerData = data.subdata(in: 0 ..< headerLength)
        let header = headerData.withUnsafeBytes({ $0.load(as: FrameHeader.self) })
        let totalLength = (headerLength + Int(header.payloadLength))

        guard header.protocolIdentifier == ReceivedFrame.protocolIdentifier else {
            // Error....
            return nil
        }

        guard data.count >= totalLength else {
            return nil
        }

        self.payloadType = header.payloadType
        self.data = data.subdata(in: headerLength ..< totalLength)
        self.length = totalLength
    }
}

final class FrameCollection {
    private let semaphore = DispatchSemaphore(value: 1)
    private var data = Data()
    private var frames: [ReceivedFrame] = []

    func add(data: Data) {
        semaphore.wait()
        self.data.append(data)

        while let frame = ReceivedFrame(from: self.data) {
            frames.append(frame)

            if self.data.count > frame.length {
                self.data = self.data.advanced(by: frame.length)
            } else {
                self.data = .init()
            }
        }
        semaphore.signal()
    }

    func next() -> ReceivedFrame? {
        semaphore.wait()
        let nextFrame = frames.isEmpty ? nil:frames.removeFirst()
        semaphore.signal()
        return nextFrame
    }
}
