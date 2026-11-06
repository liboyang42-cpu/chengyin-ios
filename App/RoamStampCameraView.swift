import AVFoundation
import SwiftUI
import UIKit

/// Preparation/review is a pushed destination. Camera capture is full-screen and camera-only;
/// no imported image or illustrative picture is ever treated as a captured stamp.
@MainActor struct RoamStampCameraView: View {
    var coordinator: RoamStampCaptureCoordinator? = nil
    var cameraEnabled = false
    var album: RoamStampAlbumContinuation? = nil
    @Environment(\.scenePhase) private var scenePhase
    private enum Focus: Hashable { case capture, status }
    @AccessibilityFocusState private var focusedControl: Focus?
    @State private var purposeAccepted = false
    @State private var showingCamera = false
    @State private var cameraIssue = false
    @State private var revision = 0
    @State private var captureGeneration = 0
    @State private var work: Task<Void, Never>?
    @State private var localDraft = RoamCityStampDraft()
    @State private var createdStampTarget: RoamCreatedStampTarget?
    var body: some View {
        let _ = revision
        Form {
            Section {
                if !cameraEnabled { Label("media.stamp.disabled", systemImage: "camera.fill") }
                if cameraIssue { Label("media.stamp.cameraIssue", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Toggle("media.stamp.consent", isOn: $purposeAccepted).disabled(isBusy || showingCamera)
            } footer: { Text("media.stamp.purpose") }
            captionSection
            if let coordinator {
                Section {
                    if let bytes = coordinator.selection?.jpeg, let image = UIImage(data: bytes) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                            .accessibilityLabel(Text("media.stamp.capturedPreview"))
                    }
                    Group {
                        if isBusy { ProgressView(LocalizedStringKey("media.stamp.phase." + phaseKey(coordinator.phase))) }
                        else { Text(LocalizedStringKey("media.stamp.phase." + phaseKey(coordinator.phase))) }
                    }.accessibilityFocused($focusedControl, equals: .status)
                    if coordinator.phase == .review {
                        Button("media.stamp.upload") { run { await coordinator.upload() } }
                            .buttonStyle(.questifyPrimary).disabled(!coordinator.canUpload)
                        Button("media.stamp.retake") { coordinator.retake(); revision += 1 }.disabled(!coordinator.canCapture)
                    }
                    if coordinator.pending != nil {
                        Button("media.stamp.create") { run { await coordinator.create() } }
                            .buttonStyle(.questifyPrimary).disabled(!coordinator.canCreate)
                    }
                    if case .created = coordinator.phase, let album {
                        Button("roam.createdStamp.open", systemImage: "rectangle.stack") {
                            guard createdStampTarget == nil else { return }
                            createdStampTarget = RoamCreatedStampTarget(phase: coordinator.phase, origin: coordinator.scope, reader: album.reader)
                        }
                        .disabled(createdStampTarget != nil || RoamCreatedStampTarget(phase: coordinator.phase, origin: coordinator.scope, reader: album.reader) == nil)
                        .accessibilityIdentifier("roam.createdStamp.open")
                    }
                }
            }
        }
        // Mini-program viewfinder shutter: one round capture button pinned at the bottom.
        .safeAreaInset(edge: .bottom) {
            if cameraEnabled, coordinator?.canCapture == true {
                Button { requestCamera() } label: {
                    ZStack {
                        Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: 4).frame(width: 76, height: 76)
                        Circle().fill(purposeAccepted ? Color.accentColor : Color.secondary.opacity(0.4)).frame(width: 62, height: 62)
                        Image(systemName: "camera.fill").font(.title2).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.bar)
                .disabled(!purposeAccepted)
                .accessibilityLabel(Text("media.stamp.capture"))
                .accessibilityIdentifier("media.stamp.capture")
                .accessibilityFocused($focusedControl, equals: .capture)
            }
        }
        .navigationTitle("media.stamp.title")
            .navigationDestination(item: $createdStampTarget) { target in
                if let album, target.isCurrent(reader: album.reader) {
                    RoamCreatedStampView(target: target, album: album)
                } else { ContentUnavailableView("roam.createdStamp.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
            }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                guard scenePhase == .active, cameraEnabled else { return }
                focusedControl = coordinator?.selection == nil ? .capture : .status
            }) {
                if cameraEnabled {
                    let ticket = captureGeneration
                    RoamNativeStampCamera { result in
                        guard ticket == captureGeneration, scenePhase == .active, cameraEnabled, purposeAccepted else { return }
                        showingCamera = false
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
                if phase == .background { invalidateCapture() }
            }
            .onChange(of: cameraEnabled) { _, enabled in if !enabled { invalidateCapture() } }
    }
    private var captionText: String { coordinator?.caption ?? localDraft.caption }
    private var captionSection: some View {
        Section("roam.experience.caption") {
            TextField("roam.experience.caption", text: Binding(get: { captionText }, set: { value in
                if let coordinator { coordinator.updateCaption(value) }
                else { localDraft.caption = value }
            }), axis: .vertical)
                .lineLimit(2...5)
                .disabled(showingCamera || !(coordinator?.canEditCaption ?? true))
                .accessibilityIdentifier("media.stamp.caption")
            HStack {
                if !RoamExperienceMath.validCaption(captionText) {
                    Label("roam.experience.captionLimit", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).accessibilityIdentifier("media.stamp.caption.limit")
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(captionText.utf16.count)/30").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityIdentifier("media.stamp.caption.remaining")
            }
        }.accessibilityIdentifier("media.stamp.caption.section")
    }
    private var isBusy: Bool { coordinator?.phase == .uploading || coordinator?.phase == .creating }
    private func invalidateCapture() {
        captureGeneration += 1; showingCamera = false; focusedControl = nil
        work?.cancel(); work = nil; coordinator?.cancel()
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
            guard !Task.isCancelled, ticket == captureGeneration, scenePhase == .active, cameraEnabled, purposeAccepted else { return }
            showingCamera = granted; cameraIssue = !granted
        }
    }
    private func stop() { captureGeneration += 1; work?.cancel(); work = nil; coordinator?.cancel(); coordinator?.changed = nil; localDraft = RoamCityStampDraft() }
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
    @Environment(\.locale) private var locale
    let finished: (Result<RetainedSelectedImage?, Error>) -> Void
    func makeUIViewController(context: Context) -> RoamStampFramingCameraController {
        RoamStampFramingCameraController(locale: locale, finished: finished)
    }
    func updateUIViewController(_ controller: RoamStampFramingCameraController, context: Context) { controller.updateLocale(locale) }
    static func dismantleUIViewController(_ controller: RoamStampFramingCameraController, coordinator: ()) { controller.invalidate() }
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
