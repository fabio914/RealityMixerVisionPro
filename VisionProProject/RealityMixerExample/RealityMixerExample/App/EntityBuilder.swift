//
//  EntityBuilder.swift
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import Foundation
import RealityKit

enum EntityBuilder {

    static let particleRadius: Float = 0.005

    static func buildParticle() -> Entity {
        let hue = Float.random(in: 0.0...1.0)
        let mass = (hue * (PhysicsConstants.maxMass - PhysicsConstants.minMass)) + PhysicsConstants.minMass

        let position = Vector3(
            Float.random(in: PhysicsConstants.minPosition.x...PhysicsConstants.maxPosition.x),
            Float.random(in: PhysicsConstants.minPosition.y...PhysicsConstants.maxPosition.y),
            Float.random(in: PhysicsConstants.minPosition.z...PhysicsConstants.maxPosition.z)
        )

        let velocity = Vector3(
            Float.random(in: -PhysicsConstants.maxDimensionalVelocity...PhysicsConstants.maxDimensionalVelocity),
            Float.random(in: -PhysicsConstants.maxDimensionalVelocity...PhysicsConstants.maxDimensionalVelocity),
            Float.random(in: -PhysicsConstants.maxDimensionalVelocity...PhysicsConstants.maxDimensionalVelocity)
        )

//        let material = SimpleMaterial(
//            color: .init(hue: CGFloat(hue), saturation: 0.8, brightness: 0.8, alpha: 1.0),
//            roughness: .float(0.5),
//            isMetallic: true
//        )

        let material = UnlitMaterial(color: .init(hue: CGFloat(hue), saturation: 0.8, brightness: 0.8, alpha: 1.0))

        let modelEntity = ModelEntity(mesh: .generateSphere(radius: particleRadius), materials: [material])
        modelEntity.components.set(ParticleComponent(mass: mass, velocity: velocity, position: position))
        modelEntity.position = position
        return modelEntity
    }

    static let lineDiameter: Float = 0.01

    static func makeLine(from positionA: SIMD3<Float>, to positionB: SIMD3<Float>, reference: Entity) -> Entity {
        let vector = SIMD3<Float>(positionA.x - positionB.x, positionA.y - positionB.y, positionA.z - positionB.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)

        let midPosition = SIMD3<Float>(
            (positionA.x + positionB.x)/2.0,
            (positionA.y + positionB.y)/2.0,
            (positionA.z + positionB.z)/2.0
        )

        let entity = reference.clone(recursive: false)
        entity.position = midPosition
        entity.look(at: positionB, from: midPosition, relativeTo: nil)

        entity.scale = .init(x: lineDiameter, y: lineDiameter, z: (lineDiameter + distance))
        return entity
    }

    static func buildBox() -> Entity {
        let referenceEntity = ModelEntity(
            mesh: .generateBox(size: 1.0),
            materials: [UnlitMaterial(color: .white)] //[SimpleMaterial(color: .init(white: 1.0, alpha: 0.5), isMetallic: false)]
        )

        let parentEntity = Entity()

        let minPosition = Vector3(
            PhysicsConstants.minPosition.x - particleRadius,
            PhysicsConstants.minPosition.y - particleRadius,
            PhysicsConstants.minPosition.z - particleRadius
        )

        let maxPosition = Vector3(
            PhysicsConstants.maxPosition.x + particleRadius,
            PhysicsConstants.maxPosition.y + particleRadius,
            PhysicsConstants.maxPosition.z + particleRadius
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(minPosition.x + lineDiameter, minPosition.y, minPosition.z),
                to: Vector3(maxPosition.x - lineDiameter, minPosition.y, minPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(maxPosition.x, minPosition.y + lineDiameter, minPosition.z),
                to: Vector3(maxPosition.x, maxPosition.y - lineDiameter, minPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(maxPosition.x - lineDiameter, maxPosition.y, minPosition.z),
                to: Vector3(minPosition.x + lineDiameter, maxPosition.y, minPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(minPosition.x, maxPosition.y - lineDiameter, minPosition.z),
                to: Vector3(minPosition.x, minPosition.y + lineDiameter, minPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(minPosition.x + lineDiameter, minPosition.y, maxPosition.z),
                to: Vector3(maxPosition.x - lineDiameter, minPosition.y, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(maxPosition.x, minPosition.y + lineDiameter, maxPosition.z),
                to: Vector3(maxPosition.x, maxPosition.y - lineDiameter, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(maxPosition.x - lineDiameter, maxPosition.y, maxPosition.z),
                to: Vector3(minPosition.x + lineDiameter, maxPosition.y, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(minPosition.x, maxPosition.y - lineDiameter, maxPosition.z),
                to: Vector3(minPosition.x, minPosition.y + lineDiameter, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(minPosition.x, minPosition.y, minPosition.z),
                to: Vector3(minPosition.x, minPosition.y, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(maxPosition.x, minPosition.y, minPosition.z),
                to: Vector3(maxPosition.x, minPosition.y, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(maxPosition.x, maxPosition.y, minPosition.z),
                to: Vector3(maxPosition.x, maxPosition.y, maxPosition.z),
                reference: referenceEntity
            )
        )

        parentEntity.addChild(
            makeLine(
                from: Vector3(minPosition.x, maxPosition.y, minPosition.z),
                to: Vector3(minPosition.x, maxPosition.y, maxPosition.z),
                reference: referenceEntity
            )
        )

        return parentEntity
    }

    static func makeBase() -> Entity {
        let meshResource = MeshResource.generateBox(size: 1.0)

        let redMaterial = UnlitMaterial(color: .red)
        let greenMaterial = UnlitMaterial(color: .green)
        let blueMaterial = UnlitMaterial(color: .blue)

        let redEntity = ModelEntity(mesh: meshResource, materials: [redMaterial])
        let greenEntity = ModelEntity(mesh: meshResource, materials: [greenMaterial])
        let blueEntity = ModelEntity(mesh: meshResource, materials: [blueMaterial])

        let length: Float = 0.1
        let diameter: Float = 0.01

        let zAxis = makeLine(from: .init(x: 0, y: 0, z: 0), to: .init(x: 0, y: 0, z: length), reference: redEntity)
        let yAxis = makeLine(from: .init(x: 0, y: diameter, z: 0), to: .init(x: 0, y: length, z: 0), reference: blueEntity)
        let xAxis = makeLine(from: .init(x: diameter, y: 0, z: 0), to: .init(x: length, y: 0, z: 0), reference: greenEntity)

        let parent = Entity()
        parent.addChild(zAxis)
        parent.addChild(yAxis)
        parent.addChild(xAxis)

        return parent
    }
}
