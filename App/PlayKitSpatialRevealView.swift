import SwiftUI
import UIKit
import AVFoundation
import ARKit
import SceneKit
import simd

@MainActor struct PlayKitSpatialRevealButton: View {
    let segment: PlayWireValue; let approval: PlayKitSpatialApproval
    let identity: String; let active: Bool
    @State private var purpose = false
    @State private var working = false
    @State private var authorizing = false
    @State private var generation = UUID()
    @State private var loadTask: Task<Void, Never>?
    @State private var issue: PlayKitSpatialError?
    @State private var prepared: Prepared?
    @State private var failedThisVisit = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var configuration: PlayKitSpatialRequest? { try? .init(segment: segment, approval: approval) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("playkitSpatial.open") { purpose = true }
                .disabled(configuration == nil || !active || working || failedThisVisit || !ARWorldTrackingConfiguration.isSupported)
            if configuration == nil { Text(LocalizedStringKey("playkitSpatial.error." + configurationError.rawValue)).font(.footnote) }
            if !ARWorldTrackingConfiguration.isSupported { Text("playkitSpatial.error.deviceUnavailable").font(.footnote) }
            if let issue { Text(LocalizedStringKey("playkitSpatial.error." + issue.rawValue)).font(.footnote) }
            if working { ProgressView("playkitSpatial.loading") }
        }
        .confirmationDialog("playkitSpatial.purpose", isPresented: $purpose, titleVisibility: .visible) {
            Button("playkitSpatial.open") { prepare() }
            Button("playkit.cancel", role: .cancel) {}
        } message: { Text("playkitSpatial.purposeDetail") }
        .sheet(item: $prepared) { item in
            PlayKitSpatialSurfaceHost(prepared: item, reduceMotion: reduceMotion, close: { prepared = nil }, fallback: {
                prepared = nil; failedThisVisit = true; issue = .deviceUnavailable
            }).presentationDetents([.large]).privacySensitive()
        }
        .onChange(of: identity) { _, _ in cancel(); failedThisVisit = false; issue = nil }
        .onChange(of: active) { _, value in if !value { cancel() } }
        .onChange(of: scenePhase) { _, value in if value == .background || (value != .active && !authorizing) { cancel() } }
        .onDisappear { if prepared == nil { cancel() } }
    }
    private var configurationError: PlayKitSpatialError {
        do { _ = try PlayKitSpatialRequest(segment: segment, approval: approval); return .disabled }
        catch { return error as? PlayKitSpatialError ?? .assetUnavailable }
    }
    private func prepare() {
        guard active, !working, !failedThisVisit, let configuration, ARWorldTrackingConfiguration.isSupported,
              let purpose = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String, !purpose.isEmpty else { return }
        generation = UUID(); let token = generation; working = true; issue = nil
        loadTask = Task {
            do {
                let image = try await PlayKitSpatialAssets.loadImage(configuration.imageURL, approvedHosts: approval.artworkHosts)
                let model: SCNScene?
                if let url = configuration.modelURL { model = try await PlayKitGLBPreparation.load(url, approvedHosts: approval.modelHosts) }
                else { model = nil }
                let marker: UIImage?
                if let url = configuration.markerURL { marker = try await PlayKitSpatialAssets.loadImage(url, approvedHosts: approval.artworkHosts) }
                else { marker = nil }
                guard token == generation, !Task.isCancelled else { return }
                let allowed: Bool
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: allowed = true
                case .notDetermined:
                    authorizing = true; allowed = await AVCaptureDevice.requestAccess(for: .video)
                default: allowed = false
                }
                guard token == generation else { return }; authorizing = false
                guard allowed else { throw PlayKitSpatialError.permissionDenied }
                guard UIApplication.shared.applicationState == .active, !Task.isCancelled else { throw PlayKitSpatialError.interrupted }
                working = false; prepared = Prepared(request: configuration, image: image, marker: marker, model: model)
            } catch {
                guard token == generation else { return }
                working = false; authorizing = false; issue = error as? PlayKitSpatialError ?? .assetUnavailable
            }
        }
    }
    private func cancel() { generation = UUID(); loadTask?.cancel(); loadTask = nil; working = false; authorizing = false; prepared = nil; purpose = false }
    struct Prepared: Identifiable {
        let id = UUID(); let request: PlayKitSpatialRequest; let image: UIImage; let marker: UIImage?; let model: SCNScene?
    }
}

@MainActor private struct PlayKitSpatialSurfaceHost: View {
    let prepared: PlayKitSpatialRevealButton.Prepared; let reduceMotion: Bool
    let close: () -> Void; let fallback: () -> Void
    @State private var phase = PlayKitSpatialPlacement.Phase.searching
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PlayKitARSurface(prepared: prepared, reduceMotion: reduceMotion, onPhase: { phase = $0 }, onFailure: fallback).ignoresSafeArea()
                VStack(spacing: 10) {
                    if phase != .placed {
                        Text(prepared.request.mode == .marker ? "playkitSpatial.findMarker" : phase == .surfaceFound ? "playkitSpatial.tapPlane" : "playkitSpatial.findPlane")
                    } else if !prepared.request.reply.isEmpty { Text(verbatim: prepared.request.reply) }
                    Text("playkitSpatial.noEvidence").font(.footnote)
                }.padding().frame(maxWidth: .infinity).background(.ultraThinMaterial).allowsHitTesting(false)
            }.navigationTitle("playkitSpatial.title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("playkit.close", action: close) }
                    ToolbarItem(placement: .primaryAction) { Button("playkitSpatial.fallback", action: fallback) }
                }
        }
        .task {
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            if phase != .placed { fallback() }
        }
    }
}

/// Real horizontal-plane raycasts and actual AR image anchors are required.
/// Nothing in this renderer calls the advanced-action or completion service.
@MainActor private struct PlayKitARSurface: UIViewRepresentable {
    let prepared: PlayKitSpatialRevealButton.Prepared; let reduceMotion: Bool
    let onPhase: (PlayKitSpatialPlacement.Phase) -> Void; let onFailure: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(prepared: prepared, reduceMotion: reduceMotion, onPhase: onPhase, onFailure: onFailure) }
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero); view.scene = SCNScene()
        view.delegate = context.coordinator; view.session.delegate = context.coordinator
        view.session.delegateQueue = .main; context.coordinator.view = view
        let configuration = ARWorldTrackingConfiguration(); configuration.planeDetection = [.horizontal]
        if prepared.request.mode == .marker {
            guard let marker = prepared.marker?.cgImage, let width = prepared.request.markerWidthMeters else {
                Task { @MainActor in onFailure() }; return view
            }
            let reference = ARReferenceImage(marker, orientation: .up, physicalWidth: CGFloat(width))
            reference.name = "task-marker"; configuration.detectionImages = [reference]; configuration.maximumNumberOfTrackedImages = 1
        }
        let gesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(gesture)
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.reduceMotion = reduceMotion
        if reduceMotion { context.coordinator.finishDecorativeMotion() }
    }
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.stopped = true; uiView.session.pause(); uiView.delegate = nil; uiView.session.delegate = nil
        uiView.scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }; coordinator.view = nil
    }
    @MainActor final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        weak var view: ARSCNView?
        let prepared: PlayKitSpatialRevealButton.Prepared; var reduceMotion: Bool
        let onPhase: (PlayKitSpatialPlacement.Phase) -> Void; let onFailure: () -> Void
        var placement = PlayKitSpatialPlacement(); var content: SCNNode?; var stopped = false
        init(prepared: PlayKitSpatialRevealButton.Prepared, reduceMotion: Bool, onPhase: @escaping (PlayKitSpatialPlacement.Phase) -> Void, onFailure: @escaping () -> Void) {
            self.prepared = prepared; self.reduceMotion = reduceMotion; self.onPhase = onPhase; self.onFailure = onFailure
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard !stopped, prepared.request.mode == .plane, let view,
                  let query = view.raycastQuery(from: gesture.location(in: view), allowing: .existingPlaneGeometry, alignment: .horizontal),
                  let result = view.session.raycast(query).first, placement.placeOnPlane(hasActualRaycast: true) else { return }
            place(transform: result.worldTransform); onPhase(placement.phase)
        }
        nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            let transform = anchor.transform
            let plane = anchor is ARPlaneAnchor, marker = anchor is ARImageAnchor
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                if self.prepared.request.mode == .plane, plane { self.placement.foundPlane(); self.onPhase(self.placement.phase) }
                if self.prepared.request.mode == .marker, marker, self.placement.lockMarker(hasActualAnchor: true) {
                    // Copy world position once into an independent root. Losing the
                    // marker does not remove or move the displayed card.
                    self.place(transform: transform); self.onPhase(self.placement.phase)
                }
            }
        }
        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor [weak self] in guard let self, !self.stopped else { return }; self.placement.fail(); self.onFailure() }
        }
        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor [weak self] in guard let self, !self.stopped else { return }; self.placement.fail(); self.onFailure() }
        }
        func finishDecorativeMotion() {
            if prepared.model != nil {
                content?.childNodes.first?.removeAllActions()
                content?.childNodes.first?.position.y = 0
                content?.childNodes.first?.scale = SCNVector3(1, 1, 1)
                return
            }
            guard let face = content?.childNodes.first,
                  let height = try? prepared.request.cardHeightMeters(imageWidth: Double(prepared.image.size.width), imageHeight: Double(prepared.image.size.height)) else { return }
            face.removeAllActions(); face.position.y = Float(height / 2); face.scale = SCNVector3(1, 1, 1)
        }
        private func place(transform: simd_float4x4) {
            guard let view, let height = try? prepared.request.cardHeightMeters(imageWidth: Double(prepared.image.size.width), imageHeight: Double(prepared.image.size.height)) else { onFailure(); return }
            content?.removeFromParentNode()
            let root = SCNNode(); root.simdPosition = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            if let model = prepared.model {
                let body = SCNNode(), fitted = SCNNode()
                for child in model.rootNode.childNodes { fitted.addChildNode(child.clone()) }
                let bounds = fitted.boundingBox
                guard let fit = try? PlayKitModelFit(min: (Double(bounds.min.x), Double(bounds.min.y), Double(bounds.min.z)),
                    max: (Double(bounds.max.x), Double(bounds.max.y), Double(bounds.max.z)), targetMeters: prepared.request.modelLongestSideMeters) else { onFailure(); return }
                fitted.scale = SCNVector3(Float(fit.scale), Float(fit.scale), Float(fit.scale))
                fitted.position = SCNVector3(Float(fit.x), Float(fit.y), Float(fit.z))
                // World upright with +Z facing the camera once. No billboard for a
                // model: the player can walk around it, even after marker loss.
                if let camera = view.pointOfView {
                    let delta = camera.simdWorldPosition - root.simdPosition
                    if hypot(delta.x, delta.z) > 0.0001 { body.eulerAngles.y = atan2(delta.x, delta.z) }
                }
                body.addChildNode(fitted); root.addChildNode(body)
                view.scene.rootNode.addChildNode(root); content = root
                view.autoenablesDefaultLighting = true
                animate(body)
                return
            }
            let board = SCNPlane(width: CGFloat(prepared.request.cardWidthMeters), height: CGFloat(height))
            let material = SCNMaterial(); material.diffuse.contents = prepared.image; material.isDoubleSided = true; material.lightingModel = .constant
            board.materials = [material]
            let face = SCNNode(geometry: board); face.position.y = Float(height / 2)
            let billboard = SCNBillboardConstraint(); billboard.freeAxes = .Y; face.constraints = [billboard]
            root.addChildNode(face); view.scene.rootNode.addChildNode(root); content = root
            animate(face)
        }
        private func animate(_ face: SCNNode) {
            guard !reduceMotion else { return }
            if prepared.request.mode == .plane {
                face.position.y += 0.3
                let drop = SCNAction.moveBy(x: 0, y: -0.3, z: 0, duration: 0.42); drop.timingMode = .easeIn
                let rise = SCNAction.moveBy(x: 0, y: 0.024, z: 0, duration: 0.09); rise.timingMode = .easeOut
                let settle = SCNAction.moveBy(x: 0, y: -0.024, z: 0, duration: 0.09); settle.timingMode = .easeIn
                face.runAction(.sequence([drop, rise, settle]))
            } else {
                face.scale = SCNVector3(0.02, 0.02, 0.02)
                let grow = SCNAction.scale(to: 1, duration: 0.52); grow.timingMode = .easeOut; face.runAction(grow)
            }
        }
    }
}
