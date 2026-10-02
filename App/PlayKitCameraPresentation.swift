import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

/// Shutter-independent framing: loading failure removes only the guide. Native
/// camera controls and the original captured pixels remain untouched.
@MainActor struct PlayKitViewfinderFrame: View {
    let frame: PlayKitPhotoFrame
    var body: some View {
        AsyncImage(url: frame.imageURL) { phase in
            if let image = phase.image { image.resizable().scaledToFit().opacity(frame.opacity) }
            else { Color.clear }
        }.padding(.horizontal, 16).allowsHitTesting(false).accessibilityHidden(true)
    }
}

@MainActor struct PlayKitCameraOverlayButton: View {
    let overlay: PlayKitScanOverlay; let identity: String
    let cameraEnabled: Bool; let active: Bool
    @State private var purpose = false
    @State private var authorizing = false
    @State private var showing = false
    @State private var failed = false
    @State private var generation = UUID()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("playkitCamera.openOverlay") { purpose = true }.disabled(!cameraEnabled || !active || authorizing)
            if !cameraEnabled { Text("playkitCamera.configGate").font(.footnote) }
            if failed { Text("playkitCamera.failedFallback").font(.footnote) }
            if authorizing { ProgressView("playkitCamera.authorizing") }
        }
        .confirmationDialog("playkitCamera.purpose", isPresented: $purpose, titleVisibility: .visible) {
            Button("playkitCamera.openOverlay") { authorize() }
            Button("playkit.cancel", role: .cancel) {}
        } message: { Text("playkitCamera.overlayPurpose") }
        .sheet(isPresented: $showing) {
            ZStack(alignment: .topTrailing) {
                PlayKitCameraOverlaySurface(overlay: overlay).ignoresSafeArea()
                Button { showing = false } label: { Label("playkit.close", systemImage: "xmark.circle.fill").padding().background(.ultraThinMaterial, in: Capsule()) }
                    .padding()
            }.privacySensitive().presentationDetents([.large])
        }
        .onChange(of: identity) { _, _ in cancel() }
        .onChange(of: active) { _, value in if !value { cancel() } }
        .onChange(of: scenePhase) { _, value in
            if value == .background || (value != .active && !authorizing) { cancel() }
        }
        .onDisappear { if !showing { cancel() } }
    }
    private func authorize() {
        guard cameraEnabled, active, !authorizing,
              UIImagePickerController.isSourceTypeAvailable(.camera), UIImagePickerController.isCameraDeviceAvailable(.rear),
              let purpose = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String, !purpose.isEmpty else { failed = true; return }
        generation = UUID(); let token = generation; authorizing = true; failed = false
        Task {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard generation == token else { return }
            authorizing = false
            guard allowed, active, scenePhase == .active, !Task.isCancelled else { failed = true; return }
            showing = true
        }
    }
    private func cancel() { generation = UUID(); authorizing = false; purpose = false; showing = false }
}

/// A screen-space camera overlay, explicitly distinct from spatial AR. The source
/// overlayScale controls image width. No shutter, QR submission or reward action.
@MainActor private struct PlayKitCameraOverlaySurface: UIViewControllerRepresentable {
    let overlay: PlayKitScanOverlay
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let camera = UIImagePickerController(); camera.sourceType = .camera; camera.cameraDevice = .rear
        camera.showsCameraControls = false; camera.isModalInPresentation = true
        let host = UIHostingController(rootView: OverlayContent(overlay: overlay))
        host.view.backgroundColor = .clear; host.view.isUserInteractionEnabled = false
        host.view.frame = camera.view.bounds; host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.host = host; camera.cameraOverlayView = host.view
        return camera
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIImagePickerController, coordinator: Coordinator) {
        controller.cameraOverlayView = nil; coordinator.host = nil
    }
    final class Coordinator { var host: UIHostingController<OverlayContent>? }
    struct OverlayContent: View {
        let overlay: PlayKitScanOverlay
        var body: some View {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()
                    AsyncImage(url: overlay.imageURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else if phase.error != nil { Text("playkit.imageUnavailable").padding().background(.ultraThinMaterial) }
                        else { ProgressView("playkit.imageLoading") }
                    }.frame(width: geometry.size.width * CGFloat(overlay.widthFraction), height: geometry.size.height * 0.55)
                    if !overlay.reply.isEmpty { Text(verbatim: overlay.reply).padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                    Text("playkitCamera.screenSpaceOnly").font(.footnote).padding().background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            }.allowsHitTesting(false)
        }
    }
}

/// System photo selection grants access only to the user-selected image. No
/// broad photo-library authorization or persistent media access is requested.
@MainActor struct PlayKitNativePhotoLibrarySheet: UIViewControllerRepresentable {
    let provider: PlayNativeDeviceProvider
    func makeCoordinator() -> Coordinator { Coordinator(provider: provider) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(); configuration.selectionLimit = 1
        configuration.filter = .images; configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let provider: PlayNativeDeviceProvider; let generation: UInt64
        init(provider: PlayNativeDeviceProvider) { self.provider = provider; generation = provider.cameraOperationGeneration }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let selected = results.first, selected.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                provider.finishCamera(nil, generation: generation); return
            }
            let provider = provider, generation = generation
            selected.itemProvider.loadObject(ofClass: UIImage.self) { value, _ in
                Task { @MainActor in provider.finishCamera(value as? UIImage, generation: generation) }
            }
        }
    }
}
