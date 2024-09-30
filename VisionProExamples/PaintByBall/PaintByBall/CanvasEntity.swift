//
//  CanvasEntity.swift
//  PaintByBall
//
//  Created by Fabio Dela Antonio on 16/09/2024.
//

import RealityKit
import UIKit
import MixedRealityCapture

enum CanvasConstants {
    static let canvasWidth: Float = 1.92
    static let canvasHeight: Float = 1.08
    static let canvasPosition = Vector3(0, 1.5, -2.0)
    static let topLeftCorner = canvasPosition + Vector3(-canvasWidth * 0.5, canvasHeight * 0.5, 0)
    static let imageSize = CGSize(width: 1920, height: 1080)
}

final class CanvasEntity: Entity {
    private var image: UIImage
    private var canvasModelEntity: ModelEntity

    @MainActor required init() {
        fatalError("init() has not been implemented")
    }

    // TODO: Replace with MTLTexture and use Blit or Shader to draw to texture.

    init?(backgroundColor: CGColor) {
        UIGraphicsBeginImageContextWithOptions(CanvasConstants.imageSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        context.setFillColor(backgroundColor)
        context.fill([
            .init(x: 0, y: 0, width: CanvasConstants.imageSize.width, height: CanvasConstants.imageSize.height)
        ])

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let image,
            let cgImage = image.cgImage,
            let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else {
            return nil
        }

        self.image = image

        let material = UnlitMaterial(texture: texture)

        let modelEntity = ModelEntity(
            mesh: .generatePlane(width: CanvasConstants.canvasWidth, depth: CanvasConstants.canvasHeight),
            materials: [material]
        )

        self.canvasModelEntity = modelEntity
        super.init()

        addChild(modelEntity)

        components.set(
            CollisionComponent(
                shapes: [.generateBox(width: CanvasConstants.canvasWidth, height: 0, depth: CanvasConstants.canvasHeight)],
                isStatic: true
            )
        )

        transform.rotation = .init(angle: .pi/2.0, axis: .init(x: 1, y: 0, z: 0))
        transform.translation = CanvasConstants.canvasPosition
    }

    func clear(with color: UIColor) {
        UIGraphicsBeginImageContextWithOptions(CanvasConstants.imageSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.setFillColor(color.cgColor)
        context.fill([
            .init(x: 0, y: 0, width: CanvasConstants.imageSize.width, height: CanvasConstants.imageSize.height)
        ])

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let image,
            let cgImage = image.cgImage,
            let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else {
            return
        }

        self.image = image
        canvasModelEntity.model?.materials = [UnlitMaterial(texture: texture)]
    }

    func draw(
        collisionPoint: Vector3,
        color: UIColor,
        radius: Float // in metres
    ) {
        let circleSize = CGSize(
            width: 2.0 * CGFloat(radius) * (CanvasConstants.imageSize.width/CGFloat(CanvasConstants.canvasWidth)),
            height: 2.0 * CGFloat(radius) * (CanvasConstants.imageSize.height/CGFloat(CanvasConstants.canvasHeight))
        )

        let intersectionPoint = collisionPoint - CanvasConstants.topLeftCorner
        let originX = intersectionPoint.x * Float(CanvasConstants.imageSize.width)/CanvasConstants.canvasWidth
        let originY = -1.0 * intersectionPoint.y * Float(CanvasConstants.imageSize.height)/CanvasConstants.canvasHeight

        let drawPoint = CGPoint(
            x: Double(originX) - Double(circleSize.width) * 0.5,
            y: Double(originY) - Double(circleSize.height) * 0.5
        )

        UIGraphicsBeginImageContextWithOptions(CanvasConstants.imageSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        image.draw(at: .zero)

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: .init(origin: drawPoint, size: circleSize))

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let image,
            let cgImage = image.cgImage,
            let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else {
            return
        }

        self.image = image
        canvasModelEntity.model?.materials = [UnlitMaterial(texture: texture)]
    }
}

enum Shooter {

    static func shootBullet(
        position: Vector3,
        finalPosition: Vector3,
        addTo parent: Entity,
        withRadius radius: Float,
        color: UIColor,
        completion: @escaping () -> Void
    ) {
        let sphereMesh = MeshResource.generateSphere(radius: radius)
        let sphereMaterial = UnlitMaterial(color: color)
        let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])

        parent.addChild(sphereEntity)
        sphereEntity.transform.translation = position

        let bulletSpeed: Float = 5.0 // m/s
        let distance = (finalPosition - position).norm
        let duration = distance/bulletSpeed

        sphereEntity.move(
            to: .init(translation: finalPosition),
            relativeTo: parent,
            duration: TimeInterval(duration),
            timingFunction: .easeIn
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(duration * 1000.0))) {
            parent.removeChild(sphereEntity)
            completion()
        }
    }
}
