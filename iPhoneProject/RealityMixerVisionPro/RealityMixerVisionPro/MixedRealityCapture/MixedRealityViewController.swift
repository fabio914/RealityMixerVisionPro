//
//  MixedRealityViewController.swift
//  iPhoneVisionProController
//
//  Created by Fabio Dela Antonio on 27/07/2024.
//

import UIKit
import SceneKit
import ARKit

import SwiftSocket

class MixedRealityViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var referenceImageView: UIImageView!

    @IBOutlet weak var topButtonsView: UIView!
    @IBOutlet weak var bottomButtonsView: UIView!

    private let client: TCPClient
    private let configuration: MixedRealityConfiguration

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    private var displayLink: CADisplayLink?
    private var hideTimer: Timer?

    private var textureCache: CVMetalTextureCache?
    private var backgroundNode: SCNNode?
    private var foregroundNode: SCNNode?

    private let sender: CameraUpdateSender
    private var receiver: MixedRealityReceiver?

    private var lastFrame: CVPixelBuffer?

    var receivedFirstFrame = false

    init(client: TCPClient, configuration: MixedRealityConfiguration) {
        self.client = client
        self.sender = CameraUpdateSender(client: client)
        self.configuration = configuration
        super.init(nibName: String(describing: type(of: self)), bundle: Bundle(for: type(of: self)))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDisplay()
        configureDisplayLink()
        configureTap()
        configureBackgroundEvent()
        configureReceiver()
        configureScene()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prepareARConfiguration()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    private func configureDisplay() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func configureDisplayLink() {
        let displayLink = CADisplayLink(target: self, selector: #selector(update(with:)))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .default)
        self.displayLink = displayLink
    }

    private func configureTap() {
        sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAction)))
    }

    private func configureBackgroundEvent() {
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    private func configureReceiver() {
        self.receiver = MixedRealityReceiver(delegate: self)
    }

    private func configureScene() {
        sceneView.rendersCameraGrain = false
        sceneView.rendersMotionBlur = false

        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.session.delegate = self

        ARKitHelpers.create(textureCache: &textureCache, for: sceneView)
    }

    private func prepareARConfiguration() {
        let configuration = ARWorldTrackingConfiguration()
//        configuration.frameSemantics = .smoothedSceneDepth
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.frameSemantics = .personSegmentationWithDepth
//        configuration.worldAlignment = .gravityAndHeading
        sceneView.session.run(configuration)
    }

    private func configureBackground(with frame: ARFrame) {
        let backgroundPlaneNode = ARKitHelpers.makePlaneNodeForDistance(100.0, frame: frame)
        backgroundPlaneNode.geometry?.firstMaterial?.transparencyMode = .rgbZero

        let surfaceShader = Shaders.backgroundSurface

        backgroundPlaneNode.geometry?.firstMaterial?.shaderModifiers = [
            .surface: surfaceShader
        ]

        sceneView.pointOfView?.addChildNode(backgroundPlaneNode)
        self.backgroundNode = backgroundPlaneNode
    }

    private func configureForeground(with frame: ARFrame) {
        let foregroundPlaneNode = ARKitHelpers.makePlaneNodeForDistance(0.01, frame: frame)
        foregroundPlaneNode.geometry?.firstMaterial?.transparencyMode = .rgbZero

        foregroundPlaneNode.geometry?.firstMaterial?.shaderModifiers = [
            .surface: Shaders.foregroundSurface
        ]

        // FIXME: Semi-transparent textures won't work with person segmentation. They'll
        // blend with the background instead of blending with the segmented image of the person.

        sceneView.pointOfView?.addChildNode(foregroundPlaneNode)
        self.foregroundNode = foregroundPlaneNode
    }

    // MARK: - Update

    @objc func update(with sender: CADisplayLink) {
        while let data = client.read(65536, timeout: 0), data.count > 0 {
            receiver?.add(data: .init(data))
        }

        receiver?.update()

        if let lastFrame = lastFrame {
            updateForegroundBackground(with: lastFrame)
        }
    }

    private func updateForegroundBackground(with pixelBuffer: CVPixelBuffer) {
        let color = ARKitHelpers.texture(from: pixelBuffer, format: .bgra8Unorm, planeIndex: 0, textureCache: textureCache)
        backgroundNode?.geometry?.firstMaterial?.diffuse.contents = color
        backgroundNode?.geometry?.firstMaterial?.transparent.contents = color

        foregroundNode?.geometry?.firstMaterial?.diffuse.contents = color
        foregroundNode?.geometry?.firstMaterial?.transparent.contents = color
    }

    // MARK: - Actions

    private func disconnect() {
        invalidate()
        dismiss(animated: false, completion: nil)
    }

    @objc private func willResignActive() {
        disconnect()
    }

    private func hideOptions() {
        hideTimer?.invalidate()
        hideTimer = nil
        topButtonsView.isHidden = true
        bottomButtonsView.isHidden = true
    }

    @objc private func tapAction() {
        guard topButtonsView.isHidden else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { [weak self] _ in
            self?.hideOptions()
        })

        topButtonsView.isHidden = false
        bottomButtonsView.isHidden = false
    }

    @IBAction private func disconnectAction(_ sender: Any) {
        disconnect()
    }

    @IBAction private func hideInterface(_ sender: Any) {
        hideOptions()
    }

    @IBAction private func hideShowCalibrationImageAction(_ sender: Any) {
        referenceImageView.isHidden = !referenceImageView.isHidden
    }

    private func invalidate() {
        client.close()
        displayLink?.invalidate()
        hideTimer?.invalidate()
    }

    deinit {
        invalidate()
    }
}

extension MixedRealityViewController: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if !receivedFirstFrame {
            configureBackground(with: frame)
            configureForeground(with: frame)
            receivedFirstFrame = true
        } else {
            sendCameraUpdate(with: frame)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    }
}

extension MixedRealityViewController {

    func sendCameraUpdate(with frame: ARFrame) {
        guard let payload = CameraUpdatePayload(frame: frame, scaleFactor: configuration.scaleFactor) else { return }
        DispatchQueue.main.async { [weak sender] in
            sender?.sendCameraUpdate(payload)
        }
    }
}

extension MixedRealityViewController: MixedRealityReceiverDelegate {

    func receiver(_ receiver: MixedRealityReceiver, didReceive pixelBuffer: CVPixelBuffer) {
        lastFrame = pixelBuffer
    }
}
