import SwiftUI
import PhotosUI

struct SquarePostLocalMediaPickerRequest: Identifiable, Equatable {
    let id: UUID
    let scope: SquarePostLocalMediaScope
}

/// Selected-item-only system UI. It does not request photo-library-wide access.
/// One pending slot mirrors the existing composer; it is not a video count policy.
@MainActor struct SquarePostLocalMediaPicker: UIViewControllerRepresentable {
    let request: SquarePostLocalMediaPickerRequest
    let completed: (NSItemProvider?, SquarePostLocalMediaPickerRequest) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(request: request, completed: completed) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let request: SquarePostLocalMediaPickerRequest
        private let completed: (NSItemProvider?, SquarePostLocalMediaPickerRequest) -> Void
        private var consumed = false
        init(request: SquarePostLocalMediaPickerRequest,
             completed: @escaping (NSItemProvider?, SquarePostLocalMediaPickerRequest) -> Void) {
            self.request = request; self.completed = completed
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !consumed else { return }; consumed = true
            if results.isEmpty { completed(nil, request) }
            else if results.count == 1 { completed(results[0].itemProvider, request) }
            else {
                // An unexpected batch is a failed selection, not Cancel or a prefix.
                // Empty provider reaches the model's explicit unresolved-media fence.
                completed(NSItemProvider(), request)
            }
        }
    }
}
