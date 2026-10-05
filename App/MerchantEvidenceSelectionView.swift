import SwiftUI
import PhotosUI

/// Native picker host. A system picker is not opened by a task, bootstrap or a fixture.
/// The default host passes false; an approved native host can enable user-initiated selection.
@MainActor struct MerchantEvidenceSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let refundID: MerchantRefundID
    let selectedScope: MerchantBusinessScope
    let currentScope: () -> MerchantBusinessScope?
    let nativeSelectionEnabled: Bool
    var cameraSelectionEnabled = false
    let selected: (MerchantEvidenceSelection) -> Void
    @State private var item: PhotosPickerItem?
    @State private var selection: MerchantEvidenceSelection?
    @State private var generation = 0
    @State private var issue: String?
    @State private var loading = false
    @State private var showingCamera = false
    var body: some View {
        Form {
            LabeledContent("merchant.engagement.refundID", value: String(refundID.rawValue))
            Text("merchant.engagement.evidenceSelectionBoundary").font(.footnote)
            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) { Label("merchant.engagement.selectEvidence", systemImage: "photo.badge.plus") }
                .disabled(!nativeSelectionEnabled).accessibilityIdentifier("merchant.engagement.evidencePicker")
            Button("merchant.engagement.captureEvidence") { showingCamera = true }
                .disabled(!cameraSelectionEnabled || !UIImagePickerController.isSourceTypeAvailable(.camera))
            if !nativeSelectionEnabled { Text("merchant.engagement.nativeSelectionDisabled").foregroundStyle(.secondary) }
            if loading { ProgressView() }
            if let selection {
                Text(selection.filename); LabeledContent("merchant.engagement.byteCount", value: String(selection.bytes.count))
                if let image = UIImage(data: selection.bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).accessibilityLabel(Text("merchant.engagement.evidencePreview")) }
                Button("merchant.engagement.reviewUpload") { guard currentScope() == selectedScope else { self.selection = nil; issue = "merchant.business.stale"; return }; selected(selection); dismiss() }
                Button("merchant.engagement.clearSelection") { generation += 1; self.selection = nil; item = nil }
            }
            if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }
        }.appNavigationTitle("merchant.engagement.evidence")
        .sheet(isPresented: $showingCamera) {
            MerchantEvidenceCameraCapture { bytes in
                showingCamera = false
                guard cameraSelectionEnabled, currentScope() == selectedScope, let bytes else { return }
                do { selection = try .importing(bytes); issue = nil } catch { issue = "merchant.engagement.evidenceInvalid" }
            }
        }
        .onChange(of: item) { _, item in
            generation += 1; let stamp = generation; selection = nil; issue = nil
            guard nativeSelectionEnabled, let item else { return }
            loading = true
            Task {
                defer { if generation == stamp { loading = false } }
                do {
                    guard let bytes = try await item.loadTransferable(type: Data.self) else { throw MerchantBusinessFailure.invalid }
                    guard stamp == generation, currentScope() == selectedScope, !Task.isCancelled else { return }; selection = try .importing(bytes)
                } catch { if stamp == generation { issue = "merchant.engagement.evidenceInvalid" } }
            }
        }
        .onDisappear { generation += 1; selection = nil; item = nil; loading = false }
    }
}

/// Native camera bridge; creation occurs only after a separate host grant and explicit user tap.
@MainActor struct MerchantEvidenceCameraCapture: UIViewControllerRepresentable {
    let result: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(result: result) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let result: (Data?) -> Void
        init(result: @escaping (Data?) -> Void) { self.result = result }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { result(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            result((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.85))
        }
    }
}
