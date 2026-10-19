import SceneKit
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// The shared room without a camera: the same scene graph on a lit floor grid,
/// orbited with a finger. Shown wherever world tracking isn't available (the
/// Simulator, a Mac, older devices) so the room can still be seen and edited.
@MainActor
final class PreviewScene: NSObject, ObservableObject, RoomCanvas {
    let scene = SCNScene()
    var onSelect: ((String?) -> Void)?

    private let root = SCNNode()
    private var nodes: [String: SCNNode] = [:]
    private var signatures: [String: String] = [:]
    private var overlays = SCNNode()
    private var spin: Float = 0

    override init() {
        super.init()
        scene.background.contents = PlatformColor.clear
        scene.rootNode.addChildNode(root)
        scene.rootNode.addChildNode(overlays)
        buildStage()
    }

    // MARK: Stage

    private func buildStage() {
        let floor = SCNNode(geometry: SCNPlane(width: 8, height: 8))
        floor.eulerAngles.x = -.pi / 2
        let material = SCNMaterial()
        material.diffuse.contents = Self.gridImage()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        // 25 cm cells.
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(32, 32, 1)
        material.diffuse.mipFilter = .linear
        material.lightingModel = .constant
        material.isDoubleSided = true
        floor.geometry?.materials = [material]
        scene.rootNode.addChildNode(floor)
        scene.fogStartDistance = 2.2
        scene.fogEndDistance = 5.5
        scene.fogColor = PlatformColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        ambient.light?.color = PlatformColor(red: 0.75, green: 0.75, blue: 1, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 520
        key.light?.castsShadow = true
        key.light?.shadowColor = PlatformColor.black.withAlphaComponent(0.45)
        key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(key)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 55
        camera.camera?.wantsHDR = true
        camera.camera?.bloomIntensity = 0.15
        camera.camera?.bloomThreshold = 1.2
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.4
        camera.position = SCNVector3(0, 1.55, 1.75)
        camera.look(at: SCNVector3(0, 0.05, -0.35))
        camera.name = "camera"
        scene.rootNode.addChildNode(camera)
    }

    /// A glowing grid tile, drawn once.
    private static func gridImage() -> Any {
        #if canImport(UIKit)
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.55, green: 0.45, blue: 1, alpha: 0.26).setStroke()
            let path = UIBezierPath(rect: CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1))
            path.lineWidth = 1
            path.stroke()
        }
        #else
        return NSColor.darkGray
        #endif
    }

    // MARK: RoomCanvas

    func placementTransform(count: Int) -> Transform? {
        // Spread new objects on a spiral in front of the camera.
        let angle = Double(count) * 2.4
        let radius = 0.1 + 0.05 * Double(count % 6)
        return .at(Vec3(cos(angle) * radius, 0.06, -0.3 + sin(angle) * radius * 0.8))
    }

    func sync(objects: [SceneObject], selected: String?, presence: [Presence], comments: [SpatialComment], me: String) {
        let want = Set(objects.map(\.id))
        for (id, node) in nodes where !want.contains(id) {
            node.removeFromParentNode()
            nodes[id] = nil
            signatures[id] = nil
        }
        for object in objects {
            let signature = "\(object.data.kind)|\(object.color)|\(object.data.content ?? "")|\(object.id == selected)"
            let node: SCNNode
            if let existing = nodes[object.id], signatures[object.id] == signature {
                node = existing
            } else {
                nodes[object.id]?.removeFromParentNode()
                node = Self.makeNode(for: object, selected: object.id == selected)
                if nodes[object.id] == nil {
                    // Pop in.
                    node.scale = SCNVector3(0.01, 0.01, 0.01)
                }
                nodes[object.id] = node
                signatures[object.id] = signature
                root.addChildNode(node)
            }
            let t = object.transform
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            node.simdPosition = t.position.simd
            node.simdOrientation = t.rotation.simd
            node.simdScale = t.scale.simd
            SCNTransaction.commit()
        }
        drawOverlays(presence: presence.filter { $0.member != me }, comments: comments)
    }

    private func drawOverlays(presence: [Presence], comments: [SpatialComment]) {
        overlays.childNodes.forEach { $0.removeFromParentNode() }
        for viewer in presence {
            let orb = SCNNode(geometry: SCNSphere(radius: 0.035))
            let material = SCNMaterial()
            material.emission.contents = PlatformColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
            material.diffuse.contents = PlatformColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
            orb.geometry?.materials = [material]
            orb.simdPosition = viewer.cameraPosition.simd
            let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.12))
            cone.geometry?.firstMaterial?.diffuse.contents = PlatformColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.25)
            cone.eulerAngles.x = -.pi / 2
            cone.position = SCNVector3(0, 0, -0.07)
            orb.addChildNode(cone)
            orb.simdOrientation = viewer.cameraRotation.simd
            overlays.addChildNode(orb)
        }
        for comment in comments {
            let pin = SCNNode(geometry: SCNSphere(radius: 0.022))
            pin.geometry?.firstMaterial?.emission.contents = PlatformColor(red: 0.96, green: 0.45, blue: 0.71, alpha: 1)
            pin.simdPosition = comment.position.simd + SIMD3(0, 0.12, 0)
            let stem = SCNNode(geometry: SCNCylinder(radius: 0.003, height: 0.1))
            stem.geometry?.firstMaterial?.diffuse.contents = PlatformColor.white.withAlphaComponent(0.5)
            stem.position = SCNVector3(0, -0.05, 0)
            pin.addChildNode(stem)
            overlays.addChildNode(pin)
        }
    }

    static func makeNode(for object: SceneObject, selected: Bool) -> SCNNode {
        let geometry: SCNGeometry
        switch object.data.kind {
        case "sphere": geometry = SCNSphere(radius: 0.06)
        case "marker":
            geometry = SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.09)
        case "arrow": geometry = SCNPyramid(width: 0.06, height: 0.12, length: 0.06)
        case "text":
            let text = SCNText(string: object.data.content ?? "", extrusionDepth: 0.6)
            text.font = .systemFont(ofSize: 4, weight: .bold)
            text.flatness = 0.2
            geometry = text
        default: geometry = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0.012)
        }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = PlatformColor(hexString: object.color)
        material.roughness.contents = 0.35
        material.metalness.contents = 0.15
        material.emission.contents = selected ? PlatformColor(hexString: object.color).withAlphaComponent(0.35) : PlatformColor.black
        geometry.materials = [material]
        let shape = SCNNode(geometry: geometry)
        if object.data.kind == "text" {
            shape.scale = SCNVector3(0.012, 0.012, 0.012)
            let (lo, hi) = shape.boundingBox
            shape.pivot = SCNMatrix4MakeTranslation((hi.x - lo.x) / 2 + lo.x, 0, 0)
        } else if object.data.kind != "marker" {
            shape.position.y = object.data.kind == "sphere" ? 0.06 : 0.05
        }
        let node = SCNNode()
        node.addChildNode(shape)
        node.name = object.id
        if selected {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.09, pipeRadius: 0.004))
            ring.geometry?.firstMaterial?.emission.contents = PlatformColor.white
            ring.geometry?.firstMaterial?.diffuse.contents = PlatformColor.white
            ring.position.y = 0.002
            node.addChildNode(ring)
        }
        return node
    }

    /// The object id under a tap, or nil for empty space.
    func objectID(in view: SCNView, at point: CGPoint) -> String? {
        for hit in view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, nodes[name] != nil { return name }
                node = current.parent
            }
        }
        return nil
    }
}

extension PlatformColor {
    convenience init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = s.count == 6 ? UInt32(s, radix: 16) ?? 0x8B5CF6 : 0x8B5CF6
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

#if canImport(UIKit)
/// The preview's view: orbit with a finger, tap to select.
struct PreviewSceneView: UIViewRepresentable {
    let scene: PreviewScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3(0, 0.05, -0.35)
        view.defaultCameraController.inertiaEnabled = true
        view.pointOfView = scene.scene.rootNode.childNode(withName: "camera", recursively: false)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.accessibilityIdentifier = "previewCanvas"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }

    @MainActor
    final class Coordinator: NSObject {
        let scene: PreviewScene
        weak var view: SCNView?
        init(scene: PreviewScene) { self.scene = scene }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            scene.onSelect?(scene.objectID(in: view, at: gesture.location(in: view)))
        }
    }
}
#endif
