//
//  RealityMixerExampleApp.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import SwiftUI
import RealityKit

@main
struct RealityMixerExampleApp: App {
    @State private var model = AppViewModel()

    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow

    var body: some SwiftUI.Scene {
        ImmersiveSpace {
            RealityView { content, attachments in
                content.add(model.setupContentEntity(attachments))
            } attachments: {

            }
            .task {
                do {
                    if model.dataProvidersAreSupported && model.isReadyToRun {
                        try await model.session.run([model.handTracking, model.imageTracking])
                    } else {
                        await dismissImmersiveSpace()
                    }
                } catch {
                    logger.error("Failed to start session: \(error)")
                    await dismissImmersiveSpace()
                    openWindow(id: "error")
                }
            }
            .task {
                await model.processHandUpdates()
            }
            .task {
                await model.processImageTrackingUpdates()
            }
            .task {
                await model.monitorSessionEvents()
            }
            .onChange(of: model.hasError) {
                openWindow(id: "error")
            }
        }
//        .upperLimbVisibility(.hidden)
        .persistentSystemOverlays(.hidden)

        WindowGroup(id: "error") {
            Text("An error occurred; check the app's logs for details.")
        }
    }

    init() {
        ParticleComponent.registerComponent()
        ForcesContainerComponent.registerComponent()
        ParticlePhysicsSystem.registerSystem()
    }
}
