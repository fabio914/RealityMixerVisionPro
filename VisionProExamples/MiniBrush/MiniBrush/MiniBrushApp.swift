//
//  MiniBrushApp.swift
//  MiniBrush
//
//  Created by Fabio Dela Antonio on 29/09/2024.
//

import SwiftUI
import RealityKit
import ARKit

@main
struct MiniBrushApp: App {
    @State private var model = AppModel()
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow

    @ViewBuilder
    var panelContent: some View {
        HStack(spacing: 40) {
            VStack(spacing: 20) {
                Button(action: model.clear) {
                    Text("Clear")
                        .font(.title)
                }

                Spacer()
                    .frame(maxHeight: 20)

                Button(action: model.quit) {
                    Text("Quit")
                        .font(.title)
                }
            }

            HStack(spacing: 20) {
                VStack(spacing: 20) {
                    VStack(spacing: 5) {
                        Text("Hue")
                            .font(.body)
                        Slider(value: $model.hue, in: 0.0...1.0)
                    }

                    VStack(spacing: 5) {
                        Text("Saturation")
                            .font(.body)
                        Slider(value: $model.saturation, in: 0.0...1.0)
                    }

                    VStack(spacing: 5) {
                        Text("Brightness")
                            .font(.body)
                        Slider(value: $model.brightness, in: 0.0...1.0)
                    }

                    VStack(spacing: 5) {
                        Text("Radius")
                            .font(.body)
                        Slider(value: $model.brushRadius, in: 0.005...0.05)
                    }

                    Toggle("Draw with left hand", isOn: $model.leftHanded)
                }

                Color(model.brushColor)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerSize: .init(width: 20.0, height: 20.0)))
            }
        }
        .padding(20)
        .glassBackgroundEffect()
    }

    var body: some SwiftUI.Scene {
        ImmersiveSpace {
            RealityView { content, attachments in
                content.add(await model.setupContentEntity(attachments: attachments))
            } attachments: {
                Attachment(id: "panel") {
                    panelContent
                }
            }
            .task {
                do {
                    if model.dataProvidersAreSupported && model.isReadyToRun {
                        try await model.session.run([model.handTracking, model.worldTracking, model.imageTracking])
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
            .onChange(of: model.errorState) {
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
        SolidBrushComponent.registerComponent()
        SolidBrushSystem.registerSystem()
    }
}
