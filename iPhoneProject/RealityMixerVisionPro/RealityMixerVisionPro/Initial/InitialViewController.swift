//
//  InitialViewController.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 25/12/2021.
//

import UIKit
import ARKit
import SwiftSocket

final class InitialViewController: UIViewController {

    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var addressTextField: UITextField!
    @IBOutlet private weak var portTextField: UITextField!

    private let preferenceStorage = PreferenceStorage()

    init() {
        super.init(nibName: String(describing: type(of: self)), bundle: Bundle(for: type(of: self)))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reality Mixer Vision Pro"

        addressTextField.delegate = self
        portTextField.delegate = self

        if let preferences = preferenceStorage.preference {
            addressTextField.text = preferences.address
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.flashScrollIndicators()
    }

    // MARK: - Actions

    @IBAction func connectAction(_ sender: Any) {

        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
        else {
            // TODO: Show alert
            return
        }

        guard let address = addressTextField.text, !address.isEmpty,
            let portText = portTextField.text, !portText.isEmpty,
            let port = Int32(portText)
        else {
            return
        }

        let connectionAlert = UIAlertController(title: "Connecting...", message: nil, preferredStyle: .alert)

        present(connectionAlert, animated: true, completion: { [weak self] in
            guard let self = self else { return }

            // FIXME: Do this in a way that doesn't block the main thread

            let client = TCPClient(address: address, port: port)

            switch client.connect(timeout: 10) {
            case .failure(let error):
                connectionAlert.dismiss(animated: false, completion: { [weak self] in

                    let alert = UIAlertController(
                        title: "Error",
                        message: "Unable to connect: \(error)",
                        preferredStyle: .alert
                    )

                    alert.addAction(.init(title: "OK", style: .default, handler: nil))

                    self?.present(alert, animated: true, completion: nil)
                })

            case .success:
                try? self.preferenceStorage.save(preference: .init(address: address))

                connectionAlert.dismiss(animated: false, completion: { [weak self] in

                    let viewController = MixedRealityViewController(
                        client: client,
                        configuration: MixedRealityConfiguration()
                    )

                    viewController.modalPresentationStyle = .overFullScreen
                    self?.present(viewController, animated: true, completion: nil)
                })
            }
        })
    }
}

extension InitialViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
}
