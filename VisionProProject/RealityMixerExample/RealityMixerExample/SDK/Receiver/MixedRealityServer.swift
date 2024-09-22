//
//  MixedRealityServer.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import SwiftSocket

protocol MixedRealityServerDelegate: AnyObject {
    func didReceiveButtonPress(_ button: UInt8)
    func didReceiveCameraUpdate(_ pose: Pose, imageSize: CGSize, verticalFOV: Float)
}

final class MixedRealityServer {
    weak var delegate: MixedRealityServerDelegate?
    private let port: Int32 = 13370

    private var server: TCPServer?
    private var client: TCPClient?

    private var serverThread: Thread?

    private var frameCollection = FrameCollection()

    func terminate() {
        serverThread?.cancel()
        serverThread = nil
        client?.close()
        client = nil
        server = nil
        frameCollection = .init()
    }

    func startServer() {
        terminate()

        let server = TCPServer(address: "0.0.0.0", port: port)
        self.server = server

        let serverThread = Thread(block: { [weak self] in
            switch server.listen() {
            case .success:
                if let client = server.accept() {
                    print("Accepted client!")
                    self?.client = client

                    while !Thread.current.isCancelled {
                        while let data = client.read(32, timeout: 0), data.count > 0 {
                            self?.frameCollection.add(data: .init(data))
                        }
                    }
                } else {
                    print("accept error")
                }
            case .failure(let error):
                print(error)
            }
        })

        serverThread.start()
        self.serverThread = serverThread
    }

    func update() {
        while let frame = frameCollection.next() {
            if let payload = ReceivedPayload(from: frame) {
                process(payload: payload)
            } else {
                // Unknown payload type...
            }
        }
    }

    func send(data: Data) {
        _ = client?.send(data: data)
    }

    private func process(payload: ReceivedPayload) {
        switch payload {
        case .buttonPress(let button):
            delegate?.didReceiveButtonPress(button)
        case let .cameraUpdate(pose, imageSize, verticalFOV):
            delegate?.didReceiveCameraUpdate(pose, imageSize: imageSize, verticalFOV: verticalFOV)
        }
    }

    init() {
    }

    deinit {
        terminate()
    }
}
