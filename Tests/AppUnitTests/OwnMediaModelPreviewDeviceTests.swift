import Foundation
import SceneKit
import XCTest
@testable import Questify

/// Synthetic scene objects and fake surfaces only; never creates SCNView or loads GLTF/network.
@MainActor private final class ModelPreviewTestSurface: OwnMediaModelPreviewSurface {
    var scene: SCNScene?, camera: SCNNode?, shows = 0, clears = 0, redraws = 0
    var onShow: (() -> Void)?, onClear: (() -> Void)?
    func show(_ scene: SCNScene, camera: SCNNode) {
        self.scene = scene; self.camera = camera; shows += 1
        let action = onShow; onShow = nil; action?()
    }
    func redraw(ifShowing scene: SCNScene) { if self.scene === scene { redraws += 1 } }
    func clear(ifShowing scene: SCNScene) {
        guard self.scene === scene else { return }; self.scene = nil; camera = nil; clears += 1
        let action = onClear; onClear = nil; action?()
    }
}
@MainActor final class OwnMediaModelPreviewDeviceTests: XCTestCase {
    private func source() -> SCNScene {
        let scene = SCNScene(); let node = SCNNode(geometry: SCNBox(width: 1, height: 2, length: 1, chamferRadius: 0))
        scene.rootNode.addChildNode(node); return scene
    }
    func testPreparationDoesNotAttachAndKeepsOriginalSceneUnchanged() throws {
        let original = source(), device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface()
        let node = try XCTUnwrap(original.rootNode.childNodes.first)
        try device.prepare(original, current: { true })
        XCTAssertEqual(original.rootNode.childNodes.count, 1); XCTAssertTrue(node.parent === original.rootNode)
        XCTAssertEqual(node.scale.x, 1); XCTAssertEqual(surface.shows, 0); device.stop()
    }
    func testPreparedSceneHasOrdinaryCameraAndOriginalFit() throws {
        let device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface()
        try device.prepare(source(), current: { true }); XCTAssertNotNil(device.attach(surface))
        let scene = try XCTUnwrap(surface.scene), camera = try XCTUnwrap(surface.camera)
        XCTAssertTrue(scene.isPaused); XCTAssertEqual(camera.position.x, 0); XCTAssertEqual(camera.position.y, 0.75); XCTAssertEqual(camera.position.z, 3)
        let fitted = try XCTUnwrap(scene.rootNode.childNodes.first?.childNodes.first)
        XCTAssertEqual(fitted.scale.x, 0.75, accuracy: 0.0001); XCTAssertEqual(fitted.position.y, 0.75, accuracy: 0.0001); device.stop()
    }
    func testExplicitRotationUses45DegreesAndWrapsWithoutAnimation() throws {
        let device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface(); try device.prepare(source(), current: { true }); XCTAssertNotNil(device.attach(surface))
        XCTAssertEqual(device.angle, 0); try device.rotate(); XCTAssertEqual(device.angle, 45); XCTAssertEqual(surface.redraws, 1)
        for _ in 0..<7 { try device.rotate() }; XCTAssertEqual(device.angle, 0); device.stop()
    }
    func testEmptySceneFailsWithoutAttachment() throws {
        let device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface()
        XCTAssertThrowsError(try device.prepare(SCNScene(), current: { true })); XCTAssertNil(device.attach(surface)); XCTAssertEqual(surface.shows, 0)
    }
    func testAuthorityIsRecheckedAtAttachAndRotate() throws {
        let device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface(); var current = true
        try device.prepare(source(), current: { current }); XCTAssertNotNil(device.attach(surface)); current = false
        XCTAssertThrowsError(try device.rotate()); XCTAssertNil(surface.scene); XCTAssertNil(device.attach(surface))
    }
    func testStopSynchronouslyClearsOnlyOwnedSurfaceAndIsIdempotent() throws {
        let device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface()
        try device.prepare(source(), current: { true }); XCTAssertNotNil(device.attach(surface))
        device.stop(); XCTAssertNil(surface.scene); XCTAssertNil(surface.camera); XCTAssertEqual(surface.clears, 1)
        device.stop(); XCTAssertEqual(surface.clears, 1)
    }
    func testOldAttachmentTeardownCannotClearReplacementAttachment() throws {
        let device = OwnMediaModelPreviewDevice(), old = ModelPreviewTestSurface(), replacement = ModelPreviewTestSurface()
        try device.prepare(source(), current: { true }); let stamp = try XCTUnwrap(device.attach(old))
        let current = try XCTUnwrap(device.attach(replacement)); XCTAssertNil(old.scene)
        device.detach(stamp); XCTAssertNotNil(replacement.scene); device.detach(current); XCTAssertNil(replacement.scene)
    }
    func testOldDeviceCannotClearSceneReplacedByAnotherDevice() throws {
        let old = OwnMediaModelPreviewDevice(), new = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface()
        try old.prepare(source(), current: { true }); XCTAssertNotNil(old.attach(surface))
        try new.prepare(source(), current: { true }); XCTAssertNotNil(new.attach(surface)); let fresh = surface.scene
        old.stop(); XCTAssertTrue(surface.scene === fresh); new.stop(); XCTAssertNil(surface.scene)
    }
    func testReentrantPrepareCannotRetireNewOwner() throws {
        let device = OwnMediaModelPreviewDevice(), replacement = source(), surface = ModelPreviewTestSurface(); var first = true
        XCTAssertThrowsError(try device.prepare(source(), current: {
            if first { first = false; try? device.prepare(replacement, current: { true }) }; return true
        }))
        XCTAssertNotNil(device.attach(surface)); XCTAssertNotNil(surface.scene); device.stop()
    }
    func testReentrantShowCannotLeaveOldSceneOrStopReplacement() throws {
        let device = OwnMediaModelPreviewDevice(), old = ModelPreviewTestSurface(), replacement = ModelPreviewTestSurface(), scene = source()
        try device.prepare(source(), current: { true })
        old.onShow = { try? device.prepare(scene, current: { true }); _ = device.attach(replacement) }
        XCTAssertNil(device.attach(old)); XCTAssertNil(old.scene); XCTAssertNotNil(replacement.scene); device.stop()
    }
    func testReentrantOldClearCannotOverwriteReplacement() throws {
        let device = OwnMediaModelPreviewDevice(), old = ModelPreviewTestSurface(), new = ModelPreviewTestSurface(), offered = ModelPreviewTestSurface(), scene = source()
        try device.prepare(source(), current: { true }); XCTAssertNotNil(device.attach(old))
        old.onClear = { try? device.prepare(scene, current: { true }); _ = device.attach(new) }
        XCTAssertNil(device.attach(offered)); XCTAssertEqual(offered.shows, 0); XCTAssertNotNil(new.scene); device.stop()
    }
    func testOldDetachAfterPrepareCannotClearNewSceneOnSameSurface() throws {
        let device = OwnMediaModelPreviewDevice(), surface = ModelPreviewTestSurface()
        try device.prepare(source(), current: { true }); let old = try XCTUnwrap(device.attach(surface))
        try device.prepare(source(), current: { true }); XCTAssertNotNil(device.attach(surface)); let fresh = surface.scene
        device.detach(old); XCTAssertTrue(surface.scene === fresh); device.stop()
    }
}
