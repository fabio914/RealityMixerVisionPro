//
//  ParticlePhysicsApp.swift
//  ParticlePhysicsApp
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import SwiftUI
import RealityKit

@main
struct ParticlePhysicsApp: App {
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
                    try await model.runSession()
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
