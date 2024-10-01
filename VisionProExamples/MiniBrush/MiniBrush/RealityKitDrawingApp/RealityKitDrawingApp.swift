/*
See the LICENSE.txt file for this sample’s licensing information.
*/

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import Collections
import Algorithms

struct SolidBrushComponent: TransientComponent {
    var generator: SolidDrawingMeshGenerator
    var material: RealityKit.Material
}

class SolidBrushSystem: System {
    private static let query = EntityQuery(where: .has(SolidBrushComponent.self))

    required init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            let brushComponent: SolidBrushComponent = entity.components[SolidBrushComponent.self]!

            // Call `update` on the generator.
            // This returns a non-nil `LowLevelMesh` if a new mesh had to be allocated.
            // This can happen when the number of samples exceeds the capacity of the mesh.
            //
            // If the generator returns a new `LowLevelMesh`,
            // apply it to the entity's `ModelComponent`.
            if let newMesh = try? brushComponent.generator.update(),
               let resource = try? MeshResource(from: newMesh) {
                if entity.components.has(ModelComponent.self) {
                    entity.components[ModelComponent.self]!.mesh = resource
                } else {
                    let modelComponent = ModelComponent(mesh: resource, materials: [brushComponent.material])
                    entity.components.set(modelComponent)
                }
            }
        }
    }
}

final class SolidDrawingMeshGenerator {
    /// The extruder this generator uses to generate the mesh geometry.
    private var extruder: CurveExtruderWithEndcaps

    /// The entity which this generator populates with mesh data.
    private let rootEntity: Entity

    var samples: [CurveSample] { extruder.samples }

    /// The bounding box RealityKit uses to perform occlusion culling.
    ///
    /// This value is `nil` if `displayMode == .editing`.
    @MainActor
    var renderBounds: BoundingBox? { extruder.renderBounds }

    @MainActor
    init(rootEntity: Entity, material: RealityKit.Material) {
        extruder = CurveExtruderWithEndcaps()
        self.rootEntity = rootEntity
        rootEntity.position = .zero
        rootEntity.components.set(SolidBrushComponent(generator: self, material: material))
    }

    @MainActor
    func update() throws -> LowLevelMesh? {
        try extruder.update()
    }

    func removeLast(sampleCount: Int) {
        extruder.removeLast(sampleCount: sampleCount)
    }

    func pushSamples(curve: [CurveSample]) {
        extruder.append(samples: curve)
    }

    func beginNewStroke() {
        extruder.beginNewStroke()
    }
}


struct CurveExtruderWithEndcaps {
    private struct BrushStroke {
        var headEndcapSamples: [CurveSample]

        var strokeSamples: [CurveSample]

        var tailEndcapSamples: [CurveSample]
    }

    var samples: [CurveSample] { strokes.last?.strokeSamples ?? [] }

    /// The bounding box RealityKit uses to perform occlusion culling.
    ///
    /// This value is `nil` if `displayMode == .editing`.
    @MainActor
    var renderBounds: BoundingBox? { extruder.renderBounds }

    /// The number of segments to use when generating endcap positions.
    ///
    /// Specifically, this is the number of segments parallel to the sweep curve (see `userCurve` in `pushStroke`).
    /// This isn't the number of radial segments, that is equal to `unitCircle.count`.
    private let endcapSegmentCount: UInt32

    /// Points on a circle with radius 1 organized counter-clockwise.
    ///
    /// The size of this array is equal to the `radialSegmentCount` passed in `init()`.
    private let unitCircle: [SIMD2<Float>]

    /// The `CurveExtruder` used to generate the mesh geometry.
    private var extruder: CurveExtruder

    /// Lookup table used to accelerate generation of endcap positions.
    ///
    /// Defined as `endcapLUT[i] = (cos(theta*i), sin(theta*i))` for `theta = (pi/2)/endcapSegmentCount`.
    /// Above `i` ranges from `1...endcapSegmentCount` inclusive.
    /// So this array has length `endcapSegmentCount`.
    private let endcapLUT: [(Float, Float)]

    private var strokes: [BrushStroke] = []

    /// Generates the `CurveSample` of the endcap given the first or last sample in a curve.
    ///
    /// - Parameters:
    ///   - sample: Either the first (if `isHeadEndcap` is true) or last (if `isHeadEndcap` is false)
    ///     sample on the curve.
    ///   - isHeadEndcap: Specifies if a head or tail endcap should be generated.
    private func generateEndcap(for sample: CurveSample, isHeadEndcap: Bool) -> [CurveSample] {
        precondition((length_squared(sample.tangent) - 1) <= 1.0e-6)

        if isHeadEndcap {
            let startPos = sample.position - sample.tangent * sample.radius
            return endcapLUT.reversed().map { (radius, oneMinusDistance) in
                let distance = 1 - oneMinusDistance
                var endcapSample = sample
                endcapSample.position = startPos + sample.tangent * sample.radius * distance
                endcapSample.radius *= radius
                return endcapSample
            }
        } else {
            return endcapLUT.map { (radius, distance) in
                var endcapSample = sample
                endcapSample.position = sample.position + sample.tangent * sample.radius * distance
                endcapSample.radius *= radius
                return endcapSample
            }
        }
    }

    /// Initializes the `CurveExtruderWithEndcaps` with the resolution of the generated geometry.
    ///
    /// - Parameters:
    ///   - radialSegmentCount: The segment count to use radially along the extruded tube.
    ///   - endcapSegmentCount: The segment count to use for endcaps.
    init(radialSegmentCount: UInt32 = 32, endcapSegmentCount: UInt32 = 16) {
        self.endcapSegmentCount = endcapSegmentCount

        // Generate a lookup table of the unit circle shape, which is swept along the curve.
        unitCircle = makeCircle(radius: 1, segmentCount: Int(radialSegmentCount))

        // Initialize the `CurveExtruder` to extrude the unit circle shape.
        extruder = CurveExtruder(shape: unitCircle)

        // Generate a lookup table `endcapLUT[i] = (cos(theta*i), sin(theta*i))`
        // for `theta = (pi/2)/endcapSegmentCount`.
        // This accelerates the generation of endcap positions (see `generateEndcap`).
        let theta = Float.pi / Float(2 * endcapSegmentCount)
        endcapLUT = (1...endcapSegmentCount).map { (cos(theta * Float($0)), sin(theta * Float($0))) }
    }

    /// Finalizes the brush stroke that is currently at the end of the list of strokes.
    ///
    /// This is necessary before rendering, and also before adding new brush strokes.
    /// Concretely, this adds a tail endcap if one does not yet exist on the last stroke.
    private mutating func finalizeLastStroke() {
        guard var last = strokes.last, !last.strokeSamples.isEmpty, last.tailEndcapSamples.isEmpty else {
            return
        }
        precondition(!last.headEndcapSamples.isEmpty,
                     "expected head endcap to exist because strokeSamples is nonempty.")
        last.tailEndcapSamples = generateEndcap(for: last.strokeSamples.last!, isHeadEndcap: false)
        extruder.append(samples: last.tailEndcapSamples)
        strokes[strokes.count - 1] = last
    }

    /// Updates the low level mesh that this curve extruder maintains.
    ///
    /// This applies pending calls to `append` or `removeLast` to the `LowLevelMesh`.
    ///
    /// - Returns: A `LowLevelMesh` if a new mesh had to be allocated (that is, the number of samples exceeded the capacity
    ///     of the previous mesh).  Returns `nil` if no new `LowLevelMesh` was allocated.
    @MainActor
    mutating func update() throws -> LowLevelMesh? {
        // Finalize the stroke which is currently at the tail of the curve.
        // This generates the tail endcap of this last stroke if it hasn't yet been generated.
        finalizeLastStroke()

        // Update the underlying `CurveExtruder` and return a `LowLevelMesh` if a new one was allocated.
        return try extruder.update()
    }

    /// Removes a number of samples from the end of the curve.
    mutating func removeLast(sampleCount strokeSamplesToRemove: Int) {
        var strokeSamplesToRemove = strokeSamplesToRemove
        while strokeSamplesToRemove > 0 {
            guard var stroke = strokes.popLast() else {
                preconditionFailure("attempted to remove more samples from the curve were added")
            }

            if !stroke.tailEndcapSamples.isEmpty {
                // Remove the tail endcap.
                extruder.removeLast(sampleCount: stroke.tailEndcapSamples.count)
                stroke.tailEndcapSamples.removeAll()
            }

            let strokeSamplesToRemoveNow = min(strokeSamplesToRemove, stroke.strokeSamples.count)
            stroke.strokeSamples.removeLast(strokeSamplesToRemoveNow)
            extruder.removeLast(sampleCount: strokeSamplesToRemoveNow)

            if stroke.strokeSamples.isEmpty && !stroke.headEndcapSamples.isEmpty {
                // Remove the head endcap.
                extruder.removeLast(sampleCount: stroke.headEndcapSamples.count)
                stroke.headEndcapSamples.removeAll()
            }

            strokeSamplesToRemove -= strokeSamplesToRemoveNow

            if strokeSamplesToRemove == 0 {
                // If there are no more samples to remove,
                // re-append `stroke` to the list of strokes.
                strokes.append(stroke)
            }
        }
    }

    /// Appends the provided curve samples to the extrusion.
    mutating func append(samples: [CurveSample]) {
        guard !samples.isEmpty else { return }
        if strokes.isEmpty { beginNewStroke() }

        var stroke = strokes.popLast()!
        precondition(stroke.headEndcapSamples.isEmpty == stroke.strokeSamples.isEmpty,
                     "expected to have generated head endcap samples if and only if there are already stroke samples")

        if !stroke.tailEndcapSamples.isEmpty {
            // Remove the tail endcap.
            extruder.removeLast(sampleCount: stroke.tailEndcapSamples.count)
            stroke.tailEndcapSamples.removeAll()
        }

        // Generate the head endcap if these are the first samples in the curve.
        if stroke.headEndcapSamples.isEmpty {
            stroke.headEndcapSamples = generateEndcap(for: samples.first!, isHeadEndcap: true)
            extruder.append(samples: stroke.headEndcapSamples)
        }

        // Append `samples` to this stroke.
        stroke.strokeSamples += samples
        extruder.append(samples: samples)

        strokes.append(stroke)
    }

    /// Begins a new stroke.
    ///
    /// This generates a tail endcap at the end of the previous extrusion (if needed),
    /// and generates a new head endcap when the next sample is added.
    mutating func beginNewStroke() {
        // Finalize the stroke currently at the tail of the curve.
        // This generates the tail endcap of this last stroke if it hasn't been generated yet.
        finalizeLastStroke()

        // Push a new stroke if the most recent stroke is not already empty.
        if strokes.isEmpty || !strokes.last!.strokeSamples.isEmpty {
            strokes.append(BrushStroke(headEndcapSamples: [], strokeSamples: [], tailEndcapSamples: []))
        }
    }
}


/// An object that represents points that a smooth curve sampler emits.
///
/// It is a point along a curve originally defined as a `CurvePoint`,
/// but smoothed into a Catmull-Rom spline.
struct CurveSample {
    /// Point data at this sample (position, radius, and so on).
    ///
    /// This is interpolated between two `CurvePoint` items, which were passed to the `SmoothCurveSampler`.
    var point: SolidBrushCurvePoint

    /// The parameter of this sample along the Catmull-Rom spline.
    ///
    /// See ``SmoothCurveSampler``.
    var parameter: Float

    var rotationFrame: simd_float3x3

    /// The distance along the spline of this sample.
    ///
    /// For example, this value is 0 if this is the first sample on the curve.
    var curveDistance: Float

    /// The position of this sample point.
    var position: SIMD3<Float> {
        get { return point.position }
        set { point.position = newValue }
    }

    var tangent: SIMD3<Float> { rotationFrame.columns.2 }

    /// The radius of this sample point.
    var radius: Float {
        get { return point.radius }
        set { point.radius = newValue }
    }

    init(point: SolidBrushCurvePoint, parameter: Float = 0, rotationFrame: simd_float3x3 = .init(diagonal: .one), curveDistance: Float = 0) {
        self.point = point
        self.parameter = parameter
        self.rotationFrame = rotationFrame
        self.curveDistance = curveDistance
    }

    init() {
        self.init(point: SolidBrushCurvePoint(
            position: .zero, radius: .zero, color: .zero//,
//            roughness: .zero, metallic: .zero
        ))
    }
}

import simd

/// An object that represents points that a solid brush style provider emits,
/// and a smooth curve sampler consumes.
struct SolidBrushCurvePoint {
    var position: SIMD3<Float>

    var radius: Float

    var color: SIMD3<Float>

//    var roughness: Float
//
//    var metallic: Float

    var positionAndRadius: SIMD4<Float> { .init(position, radius) }

    init(position: SIMD3<Float>, radius: Float, color: SIMD3<Float>/*, roughness: Float, metallic: Float*/) {
        self.position = position
        self.radius = radius
        self.color = color
//        self.roughness = roughness
//        self.metallic = metallic
    }

    init(positionAndRadius par: SIMD4<Float>, color: SIMD3<Float>/*, roughness: Float, metallic: Float*/) {
        self.position = SIMD3(par.x, par.y, par.z)
        self.radius = par.w
        self.color = color
//        self.roughness = roughness
//        self.metallic = metallic
    }
}

/// Interpolates between two solid brush curve points by a blend value.
///
/// - Parameters:
///   - point0: The first point to interpolate, corresponding with `blend == 0`.
///   - point1: The second point to interpolate, corresponding with `blend == 1`.
///   - blend: The blend of the interpolation, typically ranging from 0 to 1.
func mix(
    _ point0: SolidBrushCurvePoint, _ point1: SolidBrushCurvePoint, t blend: Float
) -> SolidBrushCurvePoint {
    SolidBrushCurvePoint(position: mix(point0.position, point1.position, t: blend),
                         radius: mix(point0.radius, point1.radius, t: blend),
                         color: mix(point0.color, point1.color, t: blend)//,
//                         roughness: mix(point0.roughness, point1.roughness, t: blend),
//                         metallic: mix(point0.metallic, point1.metallic, t: blend)
    )
}

extension SIMD3<Float> {
    /// Reinterpret a vectors X, Y, and Z components as red, green, and blue components of SwiftUI Color, respectively.
    func toColor() -> Color {
        Color(red: Double(x), green: Double(y), blue: Double(z))
    }
}

extension Color {
    /// Converts a vector binding into a color binding.  The X, Y, and Z components of the vector correspond with the
    /// red, green and blue channels of the color, respectively.
    static func makeBinding(from simdBinding: Binding<SIMD3<Float>>) -> Binding<Color> {
        return Binding<Color>(get: { simdBinding.wrappedValue.toColor() },
                              set: { simdBinding.wrappedValue = $0.toSIMD() })
    }

    /// Converts a SwiftUI Color to a vector, such that red, green, and blue maps to X, Y, and Z, respectively.
    func toSIMD(in environment: EnvironmentValues = EnvironmentValues()) -> SIMD3<Float> {
        let resolved = resolve(in: environment)
        return .init(x: resolved.red, y: resolved.green, z: resolved.blue)
    }
}

/// Returns true if `value0` and `value1` are equal within the tolerance `epsilon`.
func approximatelyEqual(_ value0: Float, _ value1: Float, epsilon: Float = 0.000_001) -> Bool {
    return abs(value0 - value1) <= epsilon
}

/// Returns true if `point0` and `point1` are equal within the tolerance `epsilon`.
func approximatelyEqual(_ point0: SIMD3<Float>, _ point1: SIMD3<Float>, epsilon: Float = 0.000_001) -> Bool {
    return distance(point0, point1) <= epsilon
}

/// Returns a rotation matrix that maps the vector `[0, 0, 1]` to `forward`.
///
/// The matrix is guaranteed to be ortho-normal (so, all columns are unit length and orthogonal).
///
/// - Parameters:
///   - forward: The returned matrix will map `[0, 0, 1]` to this value.  Behavior is undefined if this is `[0, 0, 0]`.
///   - desiredUp: The returned matrix is chosen such that it maps `[0, 1, 0]` to `desiredUp` as closely as
///         possible. Note that if `forward` and `desiredUp` are not perpendicular, the actual mapping may differ.
func orthonormalFrame(forward: SIMD3<Float> = [0, 0, 1], up desiredUp: SIMD3<Float> = [0, 1, 0]) -> simd_float3x3 {
    assert(all(isnan(forward) .== 0), "forward vector contains NaN")
    assert(all(isnan(desiredUp) .== 0), "up vector contains NaN")

    // Detect if either of the input values contains zero, and fall back to cardinal directions if so.
    let desiredUp = approximatelyEqual(desiredUp, .zero) ? [0, 1, 0] : desiredUp
    let forward = approximatelyEqual(forward, .zero) ? [0, 0, 1] : forward

    // Normalize `forward`.
    let forwardLen = length(forward)
    let forwardNorm = forward / forwardLen

    // Attempt to find a vector perpendicular to both forwardNorm and `desiredUp`.
    var right = cross(forwardNorm, desiredUp)

    // Determine if `right` has zero length. This happens when `forward` and `desiredUp` are parallel/antiparallel.
    var rightLength = length(right)
    if rightLength < 0.01 {
        right = cross(forwardNorm, SIMD3<Float>(0, 0, 1))
        rightLength = length(right)
    }

    // If `right` still has zero length then `forward` is parallel to `desiredUp` and `[0, 0, 1]`.
    if rightLength < 0.01 {
        right = cross(forwardNorm, SIMD3<Float>(1, 0, 0))
        rightLength = length(right)
    }

    // It is guaranteed mathematically that `right` has nonzero length at this point.
    right /= rightLength

    // Compute the final up vector as perpendicular to `right` and `forward`.
    // Guaranteed to be normalized as `right` and `forwardNorm` are both normalized and orthogonal.
    let finalUp = cross(right, forwardNorm)
    return simd_float3x3(columns: (-right, finalUp, forwardNorm))
}

/// Creates a 2D circle polyline centered at the origin. Points are listed in counter-clockwise order.
///
/// - Parameters:
///   - radius: Radius of the circle.
///   - segmentCount: The number of segments to use for the circle.
func makeCircle(radius: Float, segmentCount: Int) -> [SIMD2<Float>] {
    var circle: [SIMD2<Float>] = []
    circle.reserveCapacity(segmentCount)

    for segmentIndex in 0..<segmentCount {
        let radians = 2 * Float.pi * (Float(segmentIndex) / Float(segmentCount))
        circle.append(SIMD2<Float>(cos(radians), sin(radians)) * radius)
    }

    return circle
}

/// Returns a uniformly random direction, in other words a random point on a sphere with radius 1.
func randomDirection() -> SIMD3<Float> {
    // Use rejection sampling to guarantee a uniform probability over all directions.
    while true {
        let randomVector = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
        let randomVectorLength = length(randomVector)
        if randomVectorLength > 1e-8 && randomVectorLength < 1 {
            return randomVector / randomVectorLength
        }
    }
}

/// Linearly interpolates between `value0` and `value1` based on the parameter `parameter`.
///
/// `parameter = 0` corresponds with `value0` and `parameter = 1` corresponds with `value1`.
func mix(_ value0: Float, _ value1: Float, t parameter: Float) -> Float {
    return value0 + (value1 - value0) * parameter
}

/// Clamps `value` to be at least `min` and at most `max`.
func clamp(_ value: Float, min: Float, max: Float) -> Float {
    return Float.minimum(Float.maximum(value, min), max)
}

/// Applies a smoothing function to `value` such that `edge0` maps to 0, `edge1` maps to 1, and an easing curve
/// is applied to values in between.
func smoothstep (_ value: Float, minEdge edge0: Float, maxEdge edge1: Float) -> Float {
    // Scale, and clamp x to 0..1 range.
    let value = clamp((value - edge0) / (edge1 - edge0), min: 0.0, max: 1.0)
    return value * value * (3.0 - 2.0 * value)
}

/// Structure to perform an extrude operation on a 2D shape, along a 3D curve.
struct CurveExtruder {
    private var lowLevelMesh: LowLevelMesh?

    /// The default bounding box for this extruder to use when you don't specify a tighter one.
    private static let defaultBounds = BoundingBox(min: [-100, -100, -100], max: [100, 100, 100])

    /// The bounding box RealityKit uses to perform occlusion culling.
    @MainActor
    var renderBounds: BoundingBox? = nil {
        didSet {
            if let lowLevelMesh {
                // If bounds are unspecified, use arbitrarily large, default bounds.
                lowLevelMesh.parts[0].bounds = renderBounds ?? Self.defaultBounds
            }
        }
    }

    /// The shape to extrude.
    ///
    /// Assumed to be centered about the origin.
    let shape: [SIMD2<Float>]

    /// Topology of each triangle strip in the extruded solid.
    ///
    /// The topology is static and determined by the number of
    /// points on the shape.
    /// This topology is meant to be used with `MTLPrimitiveType.triangleStrip`.
    let topology: [UInt32]

    private(set) var samples: [CurveSample] = []

    /// The number of samples in `samples` that have been meshed in `lowLevelMesh`.
    private var cachedSampleCount: Int = 0

    /// The number of samples for which `lowLevelMesh` has capacity.
    @MainActor
    private var sampleCapacity: Int {
        let vertexCapacity = lowLevelMesh?.vertexCapacity ?? 0
        let indexCapacity = lowLevelMesh?.indexCapacity ?? 0

        // Each sample adds `shape.count` vertices.
        let sampleVertexCapacity = vertexCapacity / shape.count

        // Each segment between two samples adds `topology.count` indices.
        let sampleIndexCapacity = indexCapacity / topology.count + 1

        return min(sampleVertexCapacity, sampleIndexCapacity)
    }

    /// If necessary, reallocates `self.lowLevelMesh` so that the buffer size is suitable to be filled with
    /// all of the curve samples in `self.samples`.
    ///
    /// - Returns: True if a `LowLevelMesh` was reallocated. In this case, callers must reapply the `LowLevelMesh`
    ///      to their RealityKit `MeshResource`.
    @MainActor
    private mutating func reallocateMeshIfNeeded() throws -> Bool {
        guard samples.count > sampleCapacity else {
            // No need to reallocate if `sampleCapacity` is small enough.
            return false
        }

        // Double the sample capacity each time a reallocation is needed.
        var newSampleCapacity = max(sampleCapacity, 1024)
        while newSampleCapacity < samples.count {
            newSampleCapacity *= 2
        }

        // `shape` is instantiated at each sample.
        let newVertexCapacity = newSampleCapacity * shape.count

        // Each segment between two samples adds a triangle fan, which has `topology.count` indices.
        let triangleFanCapacity = newSampleCapacity - 1
        let newIndexCapacity = triangleFanCapacity * topology.count

        let newMesh = try Self.makeLowLevelMesh(vertexCapacity: newVertexCapacity, indexCapacity: newIndexCapacity)

        // The topology is fixed, so you only need to write to the index buffer once.
        newMesh.withUnsafeMutableIndices { buffer in
            // Fill the index buffer with `triangleFanCapacity` copies of the array `topology` offset for each sample.
            let typedBuffer = buffer.bindMemory(to: UInt32.self)
            for fanIndex in 0..<triangleFanCapacity {
                for vertexIndex in 0..<topology.count {
                    let bufferIndex = vertexIndex + topology.count * fanIndex
                    if topology[vertexIndex] == UInt32.max {
                        typedBuffer[bufferIndex] = UInt32.max
                    } else {
                        typedBuffer[bufferIndex] = topology[vertexIndex] + UInt32(shape.count * fanIndex)
                    }
                }
            }
        }

        if let lowLevelMesh {
            // Copy the vertex buffer from the old mesh to the new one.
            lowLevelMesh.withUnsafeBytes(bufferIndex: 0) { oldBuffer in
                newMesh.withUnsafeMutableBytes(bufferIndex: 0) { newBuffer in
                    newBuffer.copyMemory(from: oldBuffer)
                }
            }

            // Copy the parts array from the old mesh to the new one.
            newMesh.parts = lowLevelMesh.parts
        }

        lowLevelMesh = newMesh

        return true
    }

    /// Generates a `LowLevelMesh` suitable to be populated by `CurveExtruder` with the specified vertex and index capacity.
    @MainActor
    private static func makeLowLevelMesh(vertexCapacity: Int, indexCapacity: Int) throws -> LowLevelMesh {
        var descriptor = LowLevelMesh.Descriptor()

        descriptor.vertexCapacity = vertexCapacity
        descriptor.indexCapacity = indexCapacity
        descriptor.vertexAttributes = SolidBrushVertex.vertexAttributes

        let stride = MemoryLayout<SolidBrushVertex>.stride
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: stride)]

        return try LowLevelMesh(descriptor: descriptor)
    }

    /// Initializes the `CurveExtruder` with the shape to sweep along the curve.
    ///
    /// - Parameters:
    ///   - shape: The 2D shape to sweep along the curve.
    init(shape: [SIMD2<Float>]) {
        self.shape = shape

        // Compute topology //
        // Triangle fan lists each vertex in `shape` once for each ring, except for vertex `0` of `shape` which
        // is listed twice. Plus one extra index for the end-index (0xFFFFFFFF).
        let indexCountPerFan = 2 * (shape.count + 1) + 1

        var topology: [UInt32] = []
        topology.reserveCapacity(indexCountPerFan)

        // Build triangle fan.
        for vertexIndex in shape.indices.reversed() {
            topology.append(UInt32(vertexIndex))
            topology.append(UInt32(shape.count + vertexIndex))
        }

        // Wrap around to the first vertex.
        topology.append(UInt32(shape.count - 1))
        topology.append(UInt32(2 * shape.count - 1))

        // Add end-index.
        topology.append(UInt32.max)
        assert(topology.count == indexCountPerFan)

        self.topology = topology
    }

    /// Appends `samples` to the list of 3D curve samples used to generate the mesh.
    mutating func append<S: Sequence>(samples: S) where S.Element == CurveSample {
        self.samples.append(contentsOf: samples)
    }

    /// Removes samples from the end of the 3D curve which were previously added with `append`.
    mutating func removeLast(sampleCount: Int) {
        samples.removeLast(sampleCount)
        cachedSampleCount = min(cachedSampleCount, max(samples.count - 1, 0))
    }

    /// Updates the `LowLevelMesh` which is maintained by this CurveExtruder.
    ///
    /// This applies pending calls to `append` or `removeLast`
    /// to the `LowLevelMesh`.
    ///
    /// - Returns: A `LowLevelMesh` if a new mesh had to be allocated
    ///     (that is, the number of samples exceeded the capacity of the previous mesh).
    ///     Returns `nil` if no new `LowLevelMesh` was allocated.
    @MainActor
    mutating func update() throws -> LowLevelMesh? {
        let didReallocate = try reallocateMeshIfNeeded()

        if cachedSampleCount != samples.count, let lowLevelMesh {
            if cachedSampleCount < samples.count {
                lowLevelMesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBuffer in
                    let vertexBuffer = rawBuffer.bindMemory(to: SolidBrushVertex.self)
                    updateVertexBuffer(vertexBuffer)
                }
            }

            lowLevelMesh.parts.removeAll()
            if samples.count > 1 {
                let triangleFanCount = samples.count - 1

                let part = LowLevelMesh.Part(indexOffset: 0,
                                             indexCount: triangleFanCount * topology.count,
                                             topology: .triangleStrip,
                                             materialIndex: 0,
                                             bounds: renderBounds ?? Self.defaultBounds)
                lowLevelMesh.parts.append(part)
            }
        }

        return didReallocate ? lowLevelMesh : nil
    }

    /// Internal routine to update the vertex buffer of the underlying `LowLevelMesh` to include new changes to `samples`.
    private mutating func updateVertexBuffer(_ vertexBuffer: UnsafeMutableBufferPointer<SolidBrushVertex>) {
        guard cachedSampleCount < samples.count else { return }

        for sampleIndex in cachedSampleCount..<samples.count {
            let sample = samples[sampleIndex]
            let frame = sample.rotationFrame

            let previousPoint = (sampleIndex == 0) ? sample : samples[sampleIndex - 1]
            let nextPoint = (sampleIndex == samples.count - 1) ? sample : samples[sampleIndex + 1]

            let deltaRadius = nextPoint.radius - previousPoint.radius
            let deltaPosition = distance(nextPoint.position, previousPoint.position)
            let angle = atan2f(deltaRadius, deltaPosition)

            for shapeVertexIndex in 0..<shape.count {
                var vertex = SolidBrushVertex()

                // Use the rotation frame of `sample` to compute the 3D position of this vertex.
                let position2d = shape[shapeVertexIndex] * sample.point.radius
                let position3d = frame * SIMD3<Float>(position2d, 0) + sample.point.position

                // To compute the 3D bitangent, take the tangent of the shape in 2D
                // and orient with respect to the rotation frame of `sample`.
                let nextShapeIndex = (shapeVertexIndex + 1) % shape.count
                let prevShapeIndex = (shapeVertexIndex + shape.count - 1) % shape.count
                let bitangent2d = simd_normalize(shape[nextShapeIndex] - shape[prevShapeIndex])
                let bitangent3d = frame * SIMD3<Float>(bitangent2d, 0)

                // The normal is bent depending on the change in radius between adjacent samples:
                // - If the change in radius is zero, then the normal is perpendicular
                //   to `sample.tangent` and also perpendicular to `bitangent3d`.
                //   `frameNormal` is this value.
                // - As the change in radius approaches infinity, the normal approaches `sample.tangent`.
                //
                // These two extremes are blended based on the angle between the two radii (`angle`).
                // The first case above is when the angle is 0, the second case is when the angle is pi/2.
                let frameNormal = frame * SIMD3<Float>(bitangent2d.y, -bitangent2d.x, 0)
                let frameNormalToTangent = simd_quatf(from: frameNormal, to: sample.tangent)
                let frameNormalToNormal3d = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                                                       frameNormalToTangent,
                                                       -angle / (Float.pi / 2))
                let normal3d = frameNormalToNormal3d.act(frameNormal)

                // Assign vertex attributes based on the values computed above.
                vertex.position = position3d.packed3
                vertex.bitangent = bitangent3d.packed3
                vertex.normal = normal3d.packed3
                vertex.color = SIMD3<Float16>(sample.point.color).packed3
//                vertex.materialProperties = SIMD2<Float>(sample.point.roughness, sample.point.metallic)
                vertex.curveDistance = sample.curveDistance

                // Verify: This mesh generator should never output NaN.
                assert(any(isnan(vertex.position.simd3) .== 0))
                assert(any(isnan(vertex.bitangent.simd3) .== 0))
                assert(any(isnan(vertex.normal.simd3) .== 0))

                vertexBuffer[sampleIndex * shape.count + shapeVertexIndex] = vertex
            }
        }
        cachedSampleCount = samples.count
    }
}

/// A metal device to use throughout the app.
let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

/// Create a `MTLComputePipelineState` for a Metal compute kernel named `name`, using a default Metal device.
func makeComputePipeline(named name: String) -> MTLComputePipelineState? {
    if let metalDevice, let function = metalDevice.makeDefaultLibrary()?.makeFunction(name: name) {
        return try? metalDevice.makeComputePipelineState(function: function)
    } else {
        return nil
    }
}

extension MTLPackedFloat3 {
    /// Convert a `MTLPackedFloat3` to a `SIMD3<Float>`.
    var simd3: SIMD3<Float> { return .init(x, y, z) }
}

extension SIMD3 where Scalar == Float {
    /// Convert a `SIMD3<Float>` to a `MTLPackedFloat3`.
    var packed3: MTLPackedFloat3 { return .init(.init(elements: (x, y, z))) }
}

extension SIMD3 where Scalar == Float16 {
    /// Convert a `SIMD3<Float16>` to a `packed_half3`.
    var packed3: packed_half3 { return .init(x: x, y: y, z: z) }
}

extension SolidBrushVertex {
    static var vertexAttributes: [LowLevelMesh.Attribute] {
        typealias Attribute = LowLevelMesh.Attribute

        return [
            Attribute(semantic: .position, format: .float3, layoutIndex: 0,
                      offset: MemoryLayout.offset(of: \Self.position)!),

            Attribute(semantic: .normal, format: .float3, layoutIndex: 0,
                      offset: MemoryLayout.offset(of: \Self.normal)!),

            Attribute(semantic: .bitangent, format: .float3, layoutIndex: 0,
                      offset: MemoryLayout.offset(of: \Self.bitangent)!),

            Attribute(semantic: .color, format: .half3, layoutIndex: 0,
                      offset: MemoryLayout.offset(of: \Self.color)!),

            Attribute(semantic: .uv1, format: .float, layoutIndex: 0,
                      offset: MemoryLayout.offset(of: \Self.curveDistance)!),

//            Attribute(semantic: .uv3, format: .float2, layoutIndex: 0,
//                      offset: MemoryLayout.offset(of: \Self.materialProperties)!)
        ]
    }
}

private extension Collection where Element: FloatingPoint {

    /// Computes the average over this collection, omitting a number of the largest and smallest values.
    ///
    /// - Parameter truncation: The number or largest and smallest values to omit.
    /// - Returns: The mean value of the collection, after the truncated values are omitted.
    func truncatedMean(truncation: Int) -> Element {
        guard !isEmpty else { return .zero }

        var sortedSelf = Deque(sorted())
        let truncationLimit = (count - 1) / 2
        sortedSelf.removeFirst(Swift.min(truncationLimit, truncation))
        sortedSelf.removeLast(Swift.min(truncationLimit, truncation))
        return sortedSelf.reduce(Element.zero) { $0 + $1 } / Element(sortedSelf.count)
    }
}

public struct DrawingSource {
    private let rootEntity: Entity
    private var solidMaterial: RealityKit.Material

    private var solidMeshGenerator: SolidDrawingMeshGenerator
    private var smoothCurveSampler: SmoothCurveSampler

    private var inputsOverTime: Deque<(SIMD3<Float>, TimeInterval)> = []

    private var solidProvider = SolidBrushStyleProvider()

    /// The bounds of the rendered mesh.
    ///
    /// This bounds depends on `displayMode`:
    /// - When previewing, the bounds are tight to the rendered geometry.
    /// - When editing, the bounds are defined to be empty.
    @MainActor
    var renderBounds: BoundingBox {
        let solidBounds = solidMeshGenerator.renderBounds ?? BoundingBox()
        return solidBounds
    }

    @MainActor
    private mutating func trace(position: SIMD3<Float>, speed: Float, state: BrushState) {
        let settings = SolidBrushStyleProvider.Settings(thickness: state.radius, thicknessType: .uniform, color: state.color)
        let styled = solidProvider.styleInput(position: position, speed: speed, settings: settings)
        smoothCurveSampler.trace(point: styled)
    }

    @MainActor
    init(rootEntity: Entity, solidMaterial: RealityKit.Material? = nil) {
        self.rootEntity = rootEntity

        let solidMeshEntity = Entity()
        solidMeshEntity.name = "Solid brush content"
        rootEntity.addChild(solidMeshEntity)
        self.solidMaterial = solidMaterial ?? SimpleMaterial()
        solidMeshGenerator = SolidDrawingMeshGenerator(rootEntity: solidMeshEntity,
                                                       material: self.solidMaterial)
        smoothCurveSampler = SmoothCurveSampler(flatness: 0.001, generator: self.solidMeshGenerator)
    }

    @MainActor
    mutating func receiveSynthetic(position: SIMD3<Float>, speed: Float, state: BrushState) {
        trace(position: position, speed: speed, state: state)
    }

    @MainActor
    mutating func receive(input: InputData?, time: TimeInterval, state: BrushState) {
        while let (_, headTime) = inputsOverTime.first, time - headTime > 0.1 {
            inputsOverTime.removeFirst()
        }

        if let brushTip = input?.brushTip {
            let lastInputPosition = inputsOverTime.last?.0
            inputsOverTime.append((brushTip, time))

            if let lastInputPosition, lastInputPosition == brushTip {
                return
            }
        }

        let speedsOverTime = inputsOverTime.adjacentPairs().map { input0, input1 in
            let (point0, time0) = input0
            let (point1, time1) = input1
            let distance = distance(point0, point1)
            let time = abs(time0 - time1)
            return distance / Float(time)
        }

        let smoothSpeed = speedsOverTime.truncatedMean(truncation: 2)

        if let input, input.isDrawing {
            trace(position: input.brushTip, speed: smoothSpeed, state: state)
        } else {
            if !smoothCurveSampler.isEmpty {
                inputsOverTime.removeAll()
                smoothCurveSampler.beginNewStroke()
            }
        }
    }

    @MainActor
    mutating func clear() {
        rootEntity.children.first?.removeFromParent()

        let solidMeshEntity = Entity()
        solidMeshEntity.name = "Solid brush content"
        rootEntity.addChild(solidMeshEntity)
        solidMeshGenerator = SolidDrawingMeshGenerator(rootEntity: solidMeshEntity,
                                                       material: self.solidMaterial)
        smoothCurveSampler = SmoothCurveSampler(flatness: 0.001, generator: self.solidMeshGenerator)
    }
}

/// The `SmoothCurveSampler` ingests "Key Points" of a curve and smooths them into a Catmull-Rom spline.
///
/// These smoothed curve samples are submitted to a `SolidDrawingMeshGenerator` that you provide.
public struct SmoothCurveSampler {
    /// The mesh generator to submit smoothed samples to
    private(set) var curve: SolidDrawingMeshGenerator

    /// A parameter that determines how closely the generated samples should conform to the ideal smoothed curve.
    ///
    /// Lower values of flatness will result in more samples but a smoother curve.
    public let flatness: Float

    /// True if there are no points on the curve.
    var isEmpty: Bool { return keyPoints.isEmpty }

    /// An internal structure that keeps track of how the app samples key points.
    private struct KeyPoint {
        /// The number of samples generated in `keyPoints` between this key and the previous one.
        var sampleCount: Int

        /// The styled curve point at this key.
        var point: SolidBrushCurvePoint
    }

    /// All of the key points which have been submitted to the `SmoothCurveSampler.`
    private var keyPoints: [KeyPoint] = []

    private var positionSpline: LazyMapSequence<[KeyPoint], SIMD3<Float>> {
        keyPoints.lazy.map { $0.point.position }
    }

    private func samplePoint(at parameter: Float) -> SolidBrushCurvePoint {
        let radiusSpline = keyPoints.lazy.map { $0.point.radius }
        let colorSpline = keyPoints.lazy.map { $0.point.color }
//        let roughnessSpline = keyPoints.lazy.map { $0.point.roughness }
//        let metallicSpline = keyPoints.lazy.map { $0.point.metallic }

        let position = evaluateCatmullRomSpline(spline: positionSpline, parameter: parameter, derivative: false)
        let radius = evaluateCatmullRomSpline(spline: radiusSpline, parameter: parameter, derivative: false)
        let color = evaluateCatmullRomSpline(spline: colorSpline, parameter: parameter, derivative: false)
//        let roughness = evaluateCatmullRomSpline(spline: roughnessSpline, parameter: parameter, derivative: false)
//        let metallic = evaluateCatmullRomSpline(spline: metallicSpline, parameter: parameter, derivative: false)
        return SolidBrushCurvePoint(position: position, radius: radius, color: color/*, roughness: roughness, metallic: metallic*/)
    }

    private func sampleTangent(at parameter: Float) -> SIMD3<Float> {
        let derivative = evaluateCatmullRomSpline(spline: positionSpline, parameter: parameter, derivative: true)
        return approximatelyEqual(derivative, .zero) ? derivative : normalize(derivative)
    }

    private mutating func appendCurveSample(parameter: Float, overrideRotationFrame: simd_float3x3? = nil) {
        if curve.samples.isEmpty {
            precondition(approximatelyEqual(parameter, 0), "must add a point at the beginning of the curve first")
        } else {
            precondition(parameter >= curve.samples.last!.parameter, "sample parameter should be strictly increasing")
        }

        let point = samplePoint(at: parameter)
        var sample = CurveSample(point: point, parameter: parameter)

        if let lastSample = curve.samples.last {
            sample.curveDistance = lastSample.curveDistance + distance(lastSample.position, point.position)
        }

        if let overrideRotationFrame {
            sample.rotationFrame = overrideRotationFrame
        } else {
            if let lastSample = curve.samples.last {
                sample.rotationFrame = overrideRotationFrame ?? lastSample.rotationFrame
            }

            let derivative = evaluateCatmullRomSpline(
                spline: positionSpline, parameter: parameter, derivative: true
            )
            let tangent = approximatelyEqual(derivative, .zero) ? derivative : normalize(derivative)

            if !approximatelyEqual(tangent, .zero) {
                sample.rotationFrame = orthonormalFrame(forward: tangent, up: sample.rotationFrame.columns.1)
            }
        }

        curve.pushSamples(curve: [sample])

        let keyPointIndex = min(max(0, Int(parameter)), keyPoints.count - 1)
        keyPoints[keyPointIndex].sampleCount += 1
    }

    private mutating func appendCurveSamples(range: ClosedRange<Float>) {
        let samples: [Float] = subdivideCatmullRomSpline(spline: positionSpline, range: range, flatness: flatness)

        for sample in samples {
            if let lastSample = curve.samples.last {
                let maximumAngleBetweenSamples = Float.pi / 180.0 * 30
                let tangent = sampleTangent(at: sample)

                let rotationBetweenSamples = simd_quatf(from: lastSample.tangent, to: tangent)
                let angleBetweenSamples = rotationBetweenSamples.angle

                if angleBetweenSamples > maximumAngleBetweenSamples {
                    let rotationAxis = rotationBetweenSamples.axis
                    var frame = lastSample.rotationFrame
                    for angle in stride(from: maximumAngleBetweenSamples / 2, to: angleBetweenSamples, by: maximumAngleBetweenSamples) {
                        let stepRotation = simd_quatf(angle: angle, axis: rotationAxis)
                        let tangent = stepRotation.act(lastSample.tangent)
                        frame = orthonormalFrame(forward: tangent, up: frame.columns.1)

                        let parameter = mix(lastSample.parameter, sample, t: angle / angleBetweenSamples)
                        appendCurveSample(parameter: parameter, overrideRotationFrame: frame)
                    }
                }
            }

            appendCurveSample(parameter: sample)
        }
    }

    /// Pops the last key point from the curve.
    private mutating func popKeyPoint() -> SolidBrushCurvePoint? {
        guard let lastPoint = keyPoints.popLast() else { return nil }
        curve.removeLast(sampleCount: lastPoint.sampleCount)
        return lastPoint.point
    }

    init(flatness: Float, generator: SolidDrawingMeshGenerator) {
        self.flatness = flatness
        curve = generator
    }

    /// Replaces the most recently added key point with the provided `point`.
    mutating func replaceHeadKey(point: SolidBrushCurvePoint) {
        // Key point that the app is replacing with `point`.
        _ = popKeyPoint()

        trace(point: point)
    }

    /// Traces a new key point onto the end of the curve, generating smooth samples as needed.
    mutating func trace(point: SolidBrushCurvePoint) {
        if let previousPoint = popKeyPoint() {
            keyPoints.append(KeyPoint(sampleCount: 0, point: previousPoint))
        }
        keyPoints.append(KeyPoint(sampleCount: 0, point: point))

        if curve.samples.isEmpty {
            // Always sample the very beginning of the curve.
            appendCurveSample(parameter: 0)
        }

        let lastSampledParameter = curve.samples.last?.parameter ?? 0
        appendCurveSamples(range: lastSampledParameter...Float(keyPoints.count - 1))

        if let lastSampledParameter = curve.samples.last?.parameter,
           !approximatelyEqual(lastSampledParameter, Float(keyPoints.count - 1)) {
            appendCurveSample(parameter: Float(keyPoints.count - 1))
        }
    }
    /// Removes all key points from the currently-generated smooth curve, effectively beginning a new brush stroke.
    mutating func beginNewStroke() {
        keyPoints.removeAll(keepingCapacity: true)
        curve.beginNewStroke()
    }
}


public enum Chirality: Equatable {
    case left, right
}

/// Data about the current user input.
struct InputData {
    /// Location of the thumb tip `AnchorEntity`.
    var thumbTip: SIMD3<Float>

    /// Location of the index finger tip `AnchorEntity`.
    var indexFingerTip: SIMD3<Float>

    /// The location of the brush tip. This is where the person is drawing.
    var brushTip: SIMD3<Float> {
        return (thumbTip + indexFingerTip) / 2
    }

    /// True if the person is actively drawing.
    var isDrawing: Bool {
        return distance(thumbTip, indexFingerTip) < 0.015
    }
}

///// The configurations for RealityKit content in a drawing document, each suitable for different use-cases.
enum DocumentDisplayMode {
    /// Someone is editing this document.
    ///
    /// - Meshes in the document are configured with an arbitrarily large bounding box.
    /// - The root entity does not contain a `CollisionComponent`.
    /// - Updates to the `LowLevelMesh` objects in the document are enabled.
    case editing

    /// Someone is previewing or exporting this document.
    ///
    /// - Meshes in the document are configured with a tight bounding box suitable for efficient culling.
    /// - The root entity of the document is set up with a `CollisionComponent` so that the drawing can be
    ///   manipulated in Quick Look.
    /// - Updates to the `LowLevelMesh` objects in the document are disabled.
    case previewing
}

class BrushState {
    var radius: Float = 0.005
    var color: SIMD3<Float> = .init(1, 1, 1)
}

/// Stored state of the drawing.
@MainActor
class DrawingDocument {

    /// Root entity of the drawing.
    let rootEntity: Entity

    /// The bounds of the rendered mesh.
    ///
    /// This bounds depends on `displayMode`:
    /// - When previewing, the bounds are tight to the rendered geometry.
    /// - When editing, the bounds are defined to be empty.
    @MainActor
    var renderBounds: BoundingBox {
        let leftBounds = leftSource.renderBounds
        let rightBounds = rightSource.renderBounds
        return leftBounds.union(rightBounds)
    }

    /// Current settings of the brush.
    private let brushState: BrushState

    /// Drawing data from the left hand.
    private var leftSource: DrawingSource

    /// Drawing data from the right hand.
    private var rightSource: DrawingSource

    /// Time the drawing was initialized.
    private var startDate: Date

    init(brushState: BrushState) async {
        self.rootEntity = Entity()
        self.brushState = brushState
        self.startDate = .now

        let leftRootEntity = Entity()
        let rightRootEntity = Entity()
        rootEntity.addChild(leftRootEntity)
        rootEntity.addChild(rightRootEntity)

        self.rootEntity.name = "Drawing Root"
        leftRootEntity.name = "Left hand content"
        rightRootEntity.name = "Right hand content"

        var solidMaterial: RealityKit.Material = SimpleMaterial()
        if let material = try? await ShaderGraphMaterial(named: "/Root/Material",
                                                         from: "SolidBrushMaterial",
                                                         in: realityKitContentBundle) {
            solidMaterial = material
        }

        leftSource = DrawingSource(rootEntity: leftRootEntity,
                                         solidMaterial: solidMaterial)
        rightSource = DrawingSource(rootEntity: rightRootEntity,
                                          solidMaterial: solidMaterial)
    }

    func receive(input: InputData?, chirality: Chirality) {
        var input = input

        switch chirality {
        case .left:
            leftSource.receive(input: input, time: startDate.distance(to: .now), state: brushState)
        case .right:
            rightSource.receive(input: input, time: startDate.distance(to: .now), state: brushState)
        }
    }

    func clear() {
        leftSource.clear()
        rightSource.clear()
    }
}

struct SolidBrushStyleProvider {
    enum ThicknessType: Equatable, Hashable {
        case uniform

        /// - Parameters:
        ///   - viscosity: The variation in thickness the brush can vary.
        ///     This is a fraction of thickness, in the closed range `[0, 1]`.
        ///   - sensitivity: The speed in meters per second a person must draw to make the brush 50 percent wide.
        ///   - response: The difference in speed, in meters per second, to go from 50 percent brush width to 100 percent.
        case calligraphic(viscosity: Float = 0.6, sensitivity: Float = 0.755, response: Float = 0.745)
    }

    struct Settings: Equatable, Hashable {
        var thickness: Float = 0.005
        var thicknessType: ThicknessType = .uniform

        var color: SIMD3<Float> = [1, 1, 1]
//        var metallic: Float = 0
//        var roughness: Float = 0.5

        func radius(forSpeed speed: Float) -> Float {
            switch thicknessType {
            case .uniform:
                return thickness
            case let .calligraphic(viscosity, sensitivity, response):
                let radiusBlend = 1.0 - smoothstep(speed,
                                                   minEdge: sensitivity - response,
                                                   maxEdge: sensitivity + response)
                return mix(max(0.001, (1.0 - viscosity) * thickness),
                           (1.0 + viscosity) * thickness,
                           t: radiusBlend)
            }
        }
    }

    func styleInput(position: SIMD3<Float>, speed: Float, settings: Settings) -> SolidBrushCurvePoint {
        SolidBrushCurvePoint(position: position,
                             radius: settings.radius(forSpeed: speed),
                             color: settings.color//,
//                             roughness: settings.roughness,
//                             metallic: settings.metallic
        )
    }
}


// MARK: HermiteInterpolant

/// A type must support these operations for use as an interpolant in a Hermite curve.
protocol HermiteInterpolant {
    static func distance(_: Self, _: Self) -> Float
    static func length(_: Self) -> Float
    static func dot(_: Self, _: Self) -> Float
    static func + (left: Self, right: Self) -> Self
    static func - (left: Self, right: Self) -> Self
    static func * (left: Float, right: Self) -> Self
    static func * (left: Self, right: Float) -> Self
    static func / (left: Self, right: Float) -> Self
}

extension Float: HermiteInterpolant {
    static func distance(_ point0: Float, _ point1: Float) -> Float {
        return abs(point0 - point1)
    }

    static func length(_ point: Float) -> Float {
        return abs(point)
    }

    static func dot(_ point0: Self, _ point1: Self) -> Float {
        return point0 * point1
    }
}

extension SIMD2: HermiteInterpolant where Scalar == Float {
    static func distance(_ point0: SIMD2<Float>, _ point1: SIMD2<Float>) -> Float {
        return simd.distance(point0, point1)
    }

    static func length(_ point0: Self) -> Float {
        return simd.length(point0)
    }

    static func dot(_ point0: Self, _ point1: Self) -> Float {
        return simd.dot(point0, point1)
    }
}

extension SIMD3: HermiteInterpolant where Scalar == Float {
    static func distance(_ point0: SIMD3<Float>, _ point1: SIMD3<Float>) -> Float {
        return simd.distance(point0, point1)
    }

    static func length(_ point0: Self) -> Float {
        return simd.length(point0)
    }

    static func dot(_ point0: Self, _ point1: Self) -> Float {
        return simd.dot(point0, point1)
    }
}

extension SIMD4: HermiteInterpolant where Scalar == Float {
    static func distance(_ point0: SIMD4<Float>, _ point1: SIMD4<Float>) -> Float {
        return simd.distance(point0, point1)
    }

    static func length(_ point0: Self) -> Float {
        return simd.length(point0)
    }

    static func dot(_ point0: Self, _ point1: Self) -> Float {
        return simd.dot(point0, point1)
    }
}

// MARK: Hermite Curves

/// A control point on a Hermite curve is defined by its position and tangent vector (derivative).
///
/// The type of a control point can be anything that conforms to `HermiteInterpolant`.
struct HermiteControlPoint<T: HermiteInterpolant> {
    var position: T
    var tangent: T
}

/// Evaluates a cubic Hermite curve at the specified parameter with the provided control points.
///
/// - Parameters:
///   - point0: The starting control point of the curve, corresponding with `parameter == 0`.
///   - point1: The ending control point of the curve, corresponding with `parameter == 1`.
///   - parameter: The parameter value with which to interpolate the control points `point0`
///         (which corresponds to `parameter == 0`) and `point1` (which corresponds to `parameter == 1`).
///
func evaluateHermiteCurve<T: HermiteInterpolant>(_ point0: HermiteControlPoint<T>, _ point1: HermiteControlPoint<T>, parameter: Float) -> T {
    let parameter2 = parameter * parameter
    let parameter3 = parameter2 * parameter

    // The basis vectors of a classical Hermite curve.
    let p0Basis: Float = 2 * parameter3 - 3 * parameter2 + 1
    let m0Basis: Float = parameter3 - 2 * parameter2 + parameter
    let p1Basis: Float = -2 * parameter3 + 3 * parameter2
    let m1Basis: Float = parameter3 - parameter2

    let p0Term: T = p0Basis * point0.position
    let m0Term: T = m0Basis * point0.tangent
    let p1Term: T = p1Basis * point1.position
    let m1Term: T = m1Basis * point1.tangent

    return p0Term + m0Term + p1Term + m1Term
}

/// Evaluates the derivative of a cubic Hermite curve at the specified parameter with the provided control points.
///
/// - Parameters:
///   - point0: The starting control point of the curve, corresponding with `parameter == 0`.
///   - point1: The ending control point of the curve, corresponding with `parameter == 1`.
///   - parameter: The parameter value with which to interpolate the control points `point0`
///         (which corresponds to `parameter == 0`) and `point1` (which corresponds to `parameter == 1`).
func evaluateHermiteCurveDerivative<T: HermiteInterpolant>(_ point0: HermiteControlPoint<T>,
                                                           _ point1: HermiteControlPoint<T>,
                                                           parameter: Float) -> T {
    let parameter2 = parameter * parameter

    // These are the derivatives of the basis functions in `evaluateHermiteCurve()`, above.
    let p0Basis: Float = 6 * parameter2 - 6 * parameter
    let m0Basis: Float = 3 * parameter2 - 4 * parameter + 1
    let p1Basis: Float = -6 * parameter2 + 6 * parameter
    let m1Basis: Float = 3 * parameter2 - 2 * parameter

    let p0Term: T = p0Basis * point0.position
    let m0Term: T = m0Basis * point0.tangent
    let p1Term: T = p1Basis * point1.position
    let m1Term: T = m1Basis * point1.tangent

    return p0Term + m0Term + p1Term + m1Term
}

// MARK: Catmull-Rom Curves

/// Evaluates the span `point1` → `point2` of a Catmull-Rom spline at the parameter `parameter`.
///
/// A Catmull-Rom curve sampling the span `point1`↔`point2` is defined with respect to neighbor key points of
/// that span. Provide the key point before `point1` (call this `point0`) and the key point after
/// `point2` (call this `point3`).
///
/// - Parameters:
///   - point0: The key point in the Catmull-Rom Spline before `point1`.
///   - point1: The key point in the Catmull-Rom Spline corresponding with `parameter == 0`.
///   - point2: The key point in the Catmull-Rom Spline corresponding with `parameter == 1`.
///   - point3: The key point in the Catmull-Rom Spline after `point2`.
func evaluateCatmullRomCurve<T: HermiteInterpolant>(_ point0: T, _ point1: T, _ point2: T, _ point3: T, parameter: Float) -> T {
    let tangent1 = (point2 - point0) / 2
    let tangent2 = (point3 - point1) / 2

    return evaluateHermiteCurve(HermiteControlPoint(position: point1, tangent: tangent1),
                                HermiteControlPoint(position: point2, tangent: tangent2),
                                parameter: parameter)
}

/// Evaluates the derivative of the span `point1` > `point2` of a Catmull-Rom spline at the parameter `parameter`.
///
/// A Catmull-Rom curve sampling the span `point1`↔`point2` is defined with respect to neighbor key points of
/// that span. Provide the key point before `point1` (call this `point0`) and the key point after
/// `point2` (call this `point3`).
///
/// - Parameters:
///   - point0: The key point in the Catmull-Rom Spline before `point1`.
///   - point1: The key point in the Catmull-Rom Spline corresponding with `parameter == 0`.
///   - point2: The key point in the Catmull-Rom Spline corresponding with `parameter == 1`.
///   - point3: The key point in the Catmull-Rom Spline after `point2`.
func evaluateCatmullRomCurveDerivative<T: HermiteInterpolant>(_ point0: T, _ point1: T, _ point2: T, _ point3: T, parameter: Float) -> T {
    let tangent1 = (point2 - point0) / 2
    let tangent2 = (point3 - point1) / 2

    return evaluateHermiteCurveDerivative(HermiteControlPoint(position: point1, tangent: tangent1),
                                          HermiteControlPoint(position: point2, tangent: tangent2),
                                          parameter: parameter)
}

// MARK: Catmull-Rom Subdivision

private struct SubdivisionSearchItem<T> where T: Comparable {
    var range: ClosedRange<T>
    var depth: Int
}

func evaluateCatmullRomSpline<T: HermiteInterpolant, S: RandomAccessCollection<T>>(spline: S,
                                                                                   parameter: Float,
                                                                                   derivative: Bool) -> T where S.Index == Int {
    precondition(!spline.isEmpty, "Tried to evaluate an empty spline")
    guard spline.count > 1 else { return spline[0] }

    let point1Index = max(min(Int(parameter), spline.count - 2), 0)
    let point2Index = point1Index + 1

    let point1 = spline[point1Index]
    let point2 = spline[point2Index]

    let point0 = (point1Index > 0) ? spline[point1Index - 1] : (point1 + (point1 - point2))
    let point3 = (point2Index < spline.count - 1) ? spline[point2Index + 1] : (point2 + (point2 - point1))

    let spanParameter = parameter - Float(point1Index)
    if derivative {
        return evaluateCatmullRomCurveDerivative(point0, point1, point2, point3, parameter: spanParameter)
    } else {
        return evaluateCatmullRomCurve(point0, point1, point2, point3, parameter: spanParameter)
    }
}

func subdivideCatmullRomSpline<T: HermiteInterpolant, S: RandomAccessCollection<T>>(
    spline: S, range entireRange: ClosedRange<Float>, flatness: Float, maximumSubdivisionDepth: Int = 8)
-> [Float] where S.Index == Int {
    guard spline.count > 1 else { return [] }

    let evaluateCurve: (Float) -> T = {
        evaluateCatmullRomSpline(spline: spline, parameter: $0, derivative: false)
    }

    let evaluateTangent: (Float) -> T = {
        let derivative: T = evaluateCatmullRomSpline(spline: spline, parameter: $0, derivative: true)
        let length: Float = T.length(derivative)
        return approximatelyEqual(length, .zero) ? derivative : (derivative / length)
    }

    var subdivision: [Float] = []

    typealias SearchItem = SubdivisionSearchItem<Float>
    var searchItems: [SearchItem] = [SearchItem(range: entireRange, depth: 0)]

    while let item = searchItems.popLast() {
        let range = item.range
        let depth = item.depth
        guard depth < maximumSubdivisionDepth else { continue }

        let lowerPoint = evaluateCurve(range.lowerBound)
        let upperPoint = evaluateCurve(range.upperBound)

        let lowerTangent = evaluateTangent(range.lowerBound)
        let upperTangent = evaluateTangent(range.upperBound)

        let center = (range.upperBound - range.lowerBound) / 2 + range.lowerBound
        let centerPoint = evaluateCurve(center)
        let centerTangent = evaluateTangent(center)

        if T.distance((lowerPoint + upperPoint) / 2, centerPoint) > flatness
            || T.dot(lowerTangent, upperTangent) < 0.99
            || T.dot(lowerTangent, centerTangent) < 0.99
            || T.dot(centerTangent, upperTangent) < 0.99 {
            subdivision.append(center)
            searchItems.append(SearchItem(range: range.lowerBound...center, depth: depth + 1))
            searchItems.append(SearchItem(range: center...range.upperBound, depth: depth + 1))
        }
    }

    return subdivision.sorted()
}
