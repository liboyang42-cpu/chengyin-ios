import AVFoundation
import SwiftUI
import UIKit

/// Preparation/review is a pushed destination. Camera capture is full-screen and camera-only;
/// no imported image or illustrative picture is ever treated as a captured stamp.
@MainActor struct RoamStampCameraView: View {
    var coordinator: RoamStampCaptureCoordinator? = nil
    var cameraEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var purposeAccepted = false
    @State private var showingCamera = false
    @State private var cameraIssue = false
    @State private var revision = 0
    @State private var captureGeneration = 0
    @State private var work: Task<Void, Never>?
    var body: some View {
        let _ = revision
        Form {
            Section {
                Text("media.stamp.purpose")
                if !cameraEnabled { Label("media.stamp.disabled", systemImage: "camera.fill") }
                if cameraIssue { Text("media.stamp.cameraIssue") }
                Toggle("media.stamp.consent", isOn: $purposeAccepted)
            }
            if let coordinator {
                Section {
                    if let bytes = coordinator.selection?.jpeg, let image = UIImage(data: bytes) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                            .accessibilityLabel(Text("media.stamp.capturedPreview"))
                    }
                    Text(LocalizedStringKey("media.stamp.phase." + phaseKey(coordinator.phase)))
                    if coordinator.phase == .review {
                        Button("media.stamp.retake") { coordinator.retake(); revision += 1 }.disabled(!coordinator.canCapture)
                        Button("media.stamp.upload") { run { await coordinator.upload() } }.disabled(!coordinator.canUpload)
                    }
                    if coordinator.pending != nil {
                        Text("media.stamp.exactRetry")
                        Button("media.stamp.create") { run { await coordinator.create() } }.disabled(!coordinator.canCreate)
                    }
                }
            }
            Button("media.stamp.capture") { requestCamera() }
                .disabled(!cameraEnabled || !purposeAccepted || coordinator?.canCapture != true)
                .accessibilityIdentifier("media.stamp.capture")
        }.navigationTitle("media.stamp.title")
            .fullScreenCover(isPresented: $showingCamera) {
                if cameraEnabled {
                    let ticket = captureGeneration
                    RoamNativeStampCamera { result in
                        showingCamera = false
                        guard ticket == captureGeneration, scenePhase == .active else { return }
                        switch result {
                        case .success(let image): if let image { coordinator?.captured(image); revision += 1 }
                        case .failure: cameraIssue = true
                        }
                    }.ignoresSafeArea()
                }
            }
            .onAppear { coordinator?.changed = { revision += 1 } }
            .onDisappear { if !showingCamera { stop() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { captureGeneration += 1; showingCamera = false; work?.cancel(); coordinator?.cancel() }
            }
            .accessibilityIdentifier("media.stamp.destination")
    }
    private func requestCamera() {
        guard cameraEnabled, purposeAccepted, coordinator?.canCapture == true, !showingCamera else { return }
        captureGeneration += 1; let ticket = captureGeneration; cameraIssue = false
        work = Task { @MainActor in
            guard let reason = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String, !reason.isEmpty,
                  UIImagePickerController.isSourceTypeAvailable(.camera) else { cameraIssue = true; return }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let granted: Bool
            if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
            else { granted = status == .authorized }
            guard !Task.isCancelled, ticket == captureGeneration, scenePhase == .active else { return }
            showingCamera = granted; cameraIssue = !granted
        }
    }
    private func stop() { captureGeneration += 1; work?.cancel(); work = nil; coordinator?.cancel(); coordinator?.changed = nil }
    private func run(_ action: @escaping @MainActor () async -> Void) { work?.cancel(); work = Task { await action(); revision += 1 } }
    private func phaseKey(_ phase: RoamStampCaptureCoordinator.Phase) -> String {
        switch phase {
        case .ready: return "ready"
        case .review: return "review"
        case .uploading: return "uploading"
        case .awaitingCreate: return "awaitingCreate"
        case .creating: return "creating"
        case .unknown: return "unknown"
        case .created: return "created"
        case .unavailable: return "unavailable"
        case .failed: return "failed"
        }
    }
}

@MainActor struct RoamNativeStampCamera: UIViewControllerRepresentable {
    let finished: (Result<RetainedSelectedImage?, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.cameraDevice = .rear
        picker.mediaTypes = ["public.image"]; picker.delegate = context.coordinator; picker.allowsEditing = false
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIImagePickerController, coordinator: Coordinator) { controller.delegate = nil; coordinator.active = false }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var active = true
        let finished: (Result<RetainedSelectedImage?, Error>) -> Void
        init(finished: @escaping (Result<RetainedSelectedImage?, Error>) -> Void) { self.finished = finished }
        private func complete(_ result: Result<RetainedSelectedImage?, Error>) { guard active else { return }; active = false; finished(result) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { complete(.success(nil)) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            do {
                guard let image = info[.originalImage] as? UIImage else { throw RetainedImageFailure.invalid }
                complete(.success(try RoamStampPixelCrop.render(image)))
            } catch { complete(.failure(error)) }
        }
    }
}
/// Explicit 4:5 center crop is shown for review before upload. Redraw normalizes orientation,
/// resizes to 1600×2000 maximum, and never uploads the camera container's EXIF/GPS metadata.
@MainActor enum RoamStampPixelCrop {
    static func render(_ image: UIImage) throws -> RetainedSelectedImage {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 30000, size.height <= 30000, size.width * size.height <= 100_000_000 else { throw RetainedImageFailure.invalid }
        let cropWidth = min(size.width, size.height * 0.8), cropHeight = cropWidth / 0.8
        let factor = min(1, 1600 / cropWidth)
        let output = CGSize(width: floor(cropWidth * factor), height: floor(cropHeight * factor))
        guard output.width > 0, output.height > 0 else { throw RetainedImageFailure.invalid }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: output, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: output))
            image.draw(in: CGRect(x: -(size.width - cropWidth) / 2 * factor, y: -(size.height - cropHeight) / 2 * factor,
                                  width: size.width * factor, height: size.height * factor))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { throw RetainedImageFailure.invalid }
        return try RetainedImageSanitizer.sanitize(jpeg)
    }
}
