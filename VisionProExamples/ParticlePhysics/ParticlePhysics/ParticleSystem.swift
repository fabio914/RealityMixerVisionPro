//
//  ParticleSystem.swift
//  ParticlePhysicsApp
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import RealityKit
import MixedRealityCapture

enum PhysicsConstants {
    static let minPosition = Vector3(-0.5, -0.5, -0.5) // m
    static let maxPosition = Vector3(0.5, 0.5, 0.5) // m
    static let maxDimensionalVelocity: Float = 1.0 // m/s
    static let minMass: Float = 1.0 // kg
    static let maxMass: Float = 10.0 // kg
}

protocol ParticleProtocol {
    var mass: Float { get }
    var velocity: Vector3 { get }
    var position: Vector3 { get }
}

protocol ForceProtocol {
    func result(with particle: ParticleProtocol) -> Vector3
}

final class GravityForce: ForceProtocol {
    func result(with particle: ParticleProtocol) -> Vector3 {
        let gravity: Float = 9.81 * 0.05 // m/s^2
        let gravityDirection = Vector3(0, -gravity, 0)
        return gravityDirection * particle.mass
    }
}

final class AttractionForce: ForceProtocol {
    var position: Vector3

    init(position: Vector3) {
        self.position = position
    }

    func result(with particle: ParticleProtocol) -> Vector3 {
        let bigG: Float = 6.674e-11 // N*(m/kg)^2
        let bigMass: Float = 1e10
        let intensity = (bigG * bigMass * particle.mass)/(position - particle.position).magnitudeSquared
        return (position - particle.position) * intensity
    }
}

final class DragForce: ForceProtocol {
    func result(with particle: ParticleProtocol) -> Vector3 {
        let dragCoefficient: Float = -0.4
        return particle.velocity * dragCoefficient
    }
}

final class ParticleComponent: Component, ParticleProtocol {
    let mass: Float
    private(set) var velocity: Vector3
    private(set) var position: Vector3

    init(mass: Float, velocity: Vector3, position: Vector3) {
        self.mass = mass
        self.velocity = velocity
        self.position = position
    }

    func update(
        with deltaTime: TimeInterval,
        forces: [ForceProtocol],
        bounds: (Vector3, Vector3),
        maxVelocity: Float
    ) {
        position += velocity * Float(deltaTime)
        let (minPosition, maxPosition) = bounds

        if position.x > maxPosition.x {
            position.x = maxPosition.x
            velocity.x = 0
        }

        if position.y > maxPosition.y {
            position.y = maxPosition.y
            velocity.y = 0
        }

        if position.z > maxPosition.z {
            position.z = maxPosition.z
            velocity.z = 0
        }

        if position.x < minPosition.x {
            position.x = minPosition.x
            velocity.x = 0
        }

        if position.y < minPosition.y {
            position.y = minPosition.y
            velocity.y = 0
        }

        if position.z < minPosition.z {
            position.z = minPosition.z
            velocity.z = 0
        }

        var resultingForce = Vector3.zero

        for force in forces {
            resultingForce += force.result(with: self)
        }

        velocity += resultingForce * (Float(deltaTime)/mass)

        if abs(velocity.x) > maxVelocity {
            velocity.x = (velocity.x > 0) ? maxVelocity:-maxVelocity
        }

        if abs(velocity.y) > maxVelocity {
            velocity.y = (velocity.y > 0) ? maxVelocity:-maxVelocity
        }

        if abs(velocity.z) > maxVelocity {
            velocity.z = (velocity.z > 0) ? maxVelocity:-maxVelocity
        }
    }
}

final class ForcesContainerComponent: Component {
    var forces: [String: ForceProtocol]

    init(forces: [String: ForceProtocol]) {
        self.forces = forces
    }
}

final class ParticlePhysicsSystem: System {

    init(scene: RealityKit.Scene) {
    }

    func update(context: SceneUpdateContext) {
        let forceContainers = context.entities(matching: .init(where: .has(ForcesContainerComponent.self)), updatingSystemWhen: .rendering)
        let particles = context.entities(matching: .init(where: .has(ParticleComponent.self)), updatingSystemWhen: .rendering)

        let forces = Array(
            forceContainers
                .compactMap({
                    $0.components[ForcesContainerComponent.self]?.forces
                })
                .reduce([:], {
                    $0.merging($1, uniquingKeysWith: { $1 })
                })
                .values
        )

        for particle in particles {
            guard let particleComponent = particle.components[ParticleComponent.self] else { continue }
            particleComponent.update(
                with: context.deltaTime,
                forces: forces,
                bounds: (PhysicsConstants.minPosition, PhysicsConstants.maxPosition),
                maxVelocity: PhysicsConstants.maxDimensionalVelocity
            )

            particle.position = particleComponent.position
        }
    }
}
