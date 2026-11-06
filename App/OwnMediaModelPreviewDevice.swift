import Foundation
import SceneKit
import UIKit

/// Private preview surfaces accept only a prepared in-memory scene, never a URL.
@MainActor protocol OwnMediaModelPreviewSurface: AnyObject {
    func show(_ scene: SCNScene, camera: SCNNode)
    func clear(ifShowing scene: SCNScene)
    func redraw(ifShowing scene: SCNScene)
}
@MainActor protocol OwnMediaModelPreviewRendering: AnyObject {
    func prepare(_ source: SCNScene, current: @escaping () -> Bool) throws
    func rotate() throws
    func attach(_ surface: any OwnMediaModelPreviewSurface) -> UUID?
    func detach(_ attachment: UUID)
    func stop()
}

/// Ordinary virtual camera only. No ARSession, camera permission, file or network access.
@MainActor final class OwnMediaModelPreviewDevice: OwnMediaModelPreviewRendering {
    private var scene: SCNScene?, camera: SCNNode?, orbit: SCNNode?
    private weak var surface: (any OwnMediaModelPreviewSurface)?
    private var attachment: UUID?, generation = UUID()
    private var current: (() -> Bool)?
    private(set) var angle = 0

    func prepare(_ source: SCNScene, current: @escaping () -> Bool) throws {
        stop(); let run = generation; self.current = current
        do {
            guard current(), generation == run, !source.rootNode.childNodes.isEmpty else { throw OwnMediaModelPreviewFailure.stale }
            let fitted = SCNNode()
            for child in source.rootNode.childNodes { fitted.addChildNode(child.clone()) }
            let box = fitted.boundingBox
            let fit = try PlayKitModelFit(min: (Double(box.min.x), Double(box.min.y), Double(box.min.z)),
                max: (Double(box.max.x), Double(box.max.y), Double(box.max.z)), targetMeters: 1.5)
            fitted.scale = SCNVector3(Float(fit.scale), Float(fit.scale), Float(fit.scale))
            fitted.position = SCNVector3(Float(fit.x), Float(fit.y), Float(fit.z))
            let scene = SCNScene(), orbit = SCNNode(), camera = SCNNode()
            orbit.addChildNode(fitted); scene.rootNode.addChildNode(orbit)
            camera.camera = SCNCamera(); camera.camera?.fieldOfView = 45
            camera.camera?.zNear = 0.01; camera.camera?.zFar = 100
            camera.position = SCNVector3(0, 0.75, 3); scene.rootNode.addChildNode(camera)
            let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
            ambient.light?.intensity = 500; scene.rootNode.addChildNode(ambient)
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .directional
            light.light?.intensity = 1000; light.eulerAngles.x = 40 * .pi / 180; scene.rootNode.addChildNode(light)
            scene.background.contents = UIColor(white: 0.1, alpha: 1)
            scene.isPaused = true
            guard current(), generation == run else { throw OwnMediaModelPreviewFailure.stale }
            self.scene = scene; self.camera = camera; self.orbit = orbit; angle = 0
        } catch {
            if generation == run { stop() }; throw error
        }
    }
    func rotate() throws {
        let run = generation
        guard current?() == true, generation == run, let orbit else {
            if generation == run { stop() }; throw OwnMediaModelPreviewFailure.stale
        }
        angle = (angle + 45) % 360
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        orbit.eulerAngles.y = Float(angle) * .pi / 180
        SCNTransaction.commit()
        if let scene { surface?.redraw(ifShowing: scene) }
        guard current?() == true, generation == run else {
            if generation == run { stop() }; throw OwnMediaModelPreviewFailure.stale
        }
    }
    func attach(_ next: any OwnMediaModelPreviewSurface) -> UUID? {
        let run = generation
        guard current?() == true, generation == run, let scene, let camera else {
            if generation == run { stop() }; return nil
        }
        let old = surface; surface = nil; attachment = nil
        old?.clear(ifShowing: scene)
        guard current?() == true, generation == run else { return nil }
        let stamp = UUID(); surface = next; attachment = stamp
        next.show(scene, camera: camera)
        guard current?() == true, generation == run, attachment == stamp else {
            next.clear(ifShowing: scene)
            if generation == run, attachment == stamp { stop() }; return nil
        }
        return stamp
    }
    func detach(_ stamp: UUID) {
        guard attachment == stamp else { return }
        let old = surface, oldScene = scene; surface = nil; attachment = nil
        if let oldScene { old?.clear(ifShowing: oldScene) }
    }
    func stop() {
        generation = UUID(); let old = surface, oldScene = scene
        current = nil; surface = nil; attachment = nil; scene = nil; camera = nil; orbit = nil; angle = 0
        if let oldScene { old?.clear(ifShowing: oldScene) }
    }
}

/// A compare-and-clear guard prevents an old teardown from blanking a replacement scene.
@MainActor final class OwnMediaModelSceneSurface: OwnMediaModelPreviewSurface {
    private weak var view: SCNView?
    init(view: SCNView) { self.view = view }
    func show(_ scene: SCNScene, camera: SCNNode) {
        guard let view else { return }
        view.allowsCameraControl = false; view.autoenablesDefaultLighting = false
        view.rendersContinuously = false; view.isPlaying = false
        view.scene = scene; view.pointOfView = camera; view.isHidden = false
        view.setNeedsDisplay()
    }
    func redraw(ifShowing scene: SCNScene) {
        guard let view, view.scene === scene else { return }; view.setNeedsDisplay()
    }
    func clear(ifShowing scene: SCNScene) {
        guard let view, view.scene === scene else { return }
        view.isPlaying = false; view.rendersContinuously = false
        view.isHidden = true; view.scene = nil; view.pointOfView = nil; view.setNeedsDisplay()
    }
}
