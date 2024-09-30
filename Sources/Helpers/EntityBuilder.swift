import RealityKit

public enum EntityBuilder {

    public static func makeLine(
        from positionA: SIMD3<Float>,
        to positionB: SIMD3<Float>,
        lineDiameter: Float = 0.01,
        reference: Entity
    ) -> Entity {
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

    public static func makeGizmo() -> Entity {
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
