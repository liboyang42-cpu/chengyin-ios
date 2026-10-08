import Foundation

/// Topic-specific selection seam. The shared picker only supplies selected, redrawn
/// JPEG bytes; it grants neither a topic upload nor permission to modify a draft.
@MainActor protocol ProjectTopicMediaPicking: AnyObject {
    func select() async throws -> RetainedSelectedImage?
    func cancel()
}
@MainActor final class ProjectTopicMediaPicker: ProjectTopicMediaPicking {
    private let picker: RetainedNativeImagePicker
    init(host: RetainedImagePickerHost, permitted: @escaping () -> Bool) {
        picker = host.makePicker(selectionApproval: permitted)
    }
    func select() async throws -> RetainedSelectedImage? { try await picker.select() }
    func cancel() { picker.cancel() }
}
