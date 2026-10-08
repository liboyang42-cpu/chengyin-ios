import SwiftUI
import Observation
import UIKit
import UniformTypeIdentifiers

struct SquarePostLocalMediaImageUpload {
    let reference: SquarePostLocalMediaReference
    let scope: SquarePostLocalMediaScope
    let bytes: Data
    let mimeType: String
}

enum SquarePostLocalMediaPresentationState: Equatable {
    case empty, choosing, loading, imagePreview, videoUnavailable, cancelled, failed, expired
}

/// A single pending local attachment beside the existing uploaded-media list.
/// The registry owns bounded immutable Data and decoded thumbnail pixels. URLs,
/// provider filenames and asset identifiers are never retained or persisted.
@MainActor @Observable final class SquarePostLocalMediaPresentation {
    private(set) var state: SquarePostLocalMediaPresentationState = .empty
    private(set) var pickerRequest: SquarePostLocalMediaPickerRequest?
    private(set) var previewRequest: UUID?
    private(set) var scope: SquarePostLocalMediaScope?
    private(set) var selectedKind: SquarePostLocalMediaKind?
    private(set) var unresolvedSelection = false
    private(set) var discardedCallbacks = 0
    private var selection: SquarePostLocalMediaSelection?
    private var image: SquarePostLocalMediaImagePreview?
    private(set) var loadTask: Task<Void, Never>?
    private var activeInspection: SquarePostLocalMediaInspectionToken?
    typealias ImageLoader = @MainActor (NSItemProvider, UTType, Int, SquarePostLocalMediaByteInspection) async throws -> SquarePostLocalMediaImagePreview
    private let imageLoader: ImageLoader
    init(imageLoader: @escaping ImageLoader = { provider, type, limit, inspection in
        try await SquarePostLocalMediaInspector.loadImage(provider: provider, type: type, maximumBytes: limit, inspection: inspection)
    }) { self.imageLoader = imageLoader }
    var thumbnail: UIImage? { image?.thumbnail }
    var hasSelection: Bool { selectedKind != nil || unresolvedSelection }
    var snapshot: SquarePostLocalMediaSnapshot? { selection?.snapshot }
    var imageUpload: SquarePostLocalMediaImageUpload? {
        guard state == .imagePreview, let image, let scope,
              let item = selection?.items.first,
              case .bytesBoundMetadata(let evidence) = item.phase,
              evidence == image.evidence else { return nil }
        return .init(reference: evidence.token.reference, scope: scope, bytes: image.bytes,
                     mimeType: evidence.description.mimeType)
    }
    func bind(scope: SquarePostLocalMediaScope) {
        guard self.scope != scope else { return }
        invalidate(); self.scope = scope
        // No invented total/video policy. Core still provides reference/attempt fencing
        // and actual byte evidence; the existing image upload gate remains separate.
        selection = SquarePostLocalMediaSelection(scope: scope)
        state = .empty
    }
    func beginPicker(scope: SquarePostLocalMediaScope) {
        bind(scope: scope); closePreview()
        if state == .loading { cancelInspection() }
        pickerRequest = .init(id: UUID(), scope: scope)
        if !hasSelection { state = .choosing }
    }
    func cancelPicker() {
        guard pickerRequest != nil else { return }
        pickerRequest = nil
        if state == .choosing { state = .cancelled }
        // A dismissed reselection keeps the previously selected image intact.
    }
    @discardableResult func accept(provider: NSItemProvider?, request: SquarePostLocalMediaPickerRequest,
                                    maximumImageBytes: Int, scopeIsCurrent: @escaping () -> Bool) -> Bool {
        guard pickerRequest == request, scope == request.scope else { discardedCallbacks += 1; return false }
        guard scopeIsCurrent() else { invalidate(); return false }
        guard let provider else { cancelPicker(); return true }
        // A movie may also advertise a still-image representation. Never downgrade
        // that selection to its JPEG poster to bypass the missing video contract.
        let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let imageType = isVideo ? nil : SquarePostLocalMediaInspector.imageType(in: provider)
        guard imageType != nil || isVideo else {
            pickerRequest = nil; remove(); unresolvedSelection = true; state = .failed; return false
        }
        guard let inspection = beginSelection(kind: isVideo ? .video : .image, request: request) else {
            return isVideo && state == .videoUnavailable
        }
        guard let imageType else { return false }
        let imageLoader = imageLoader
        loadTask = Task { [weak self] in
            do {
                let result = try await imageLoader(provider, imageType, maximumImageBytes, inspection)
                guard let self else { return }
                guard self.activeInspection == inspection.token else { self.discardedCallbacks += 1; return }
                guard scopeIsCurrent() else { self.invalidate(); return }
                guard !Task.isCancelled else { return }
                _ = self.complete(result)
            } catch {
                guard let self else { return }
                guard self.activeInspection == inspection.token else { self.discardedCallbacks += 1; return }
                guard scopeIsCurrent() else { self.invalidate(); return }
                self.fail(inspection.token, cancelled: error is CancellationError)
            }
        }
        return true
    }
    /// Internal seam also used by synthetic unit tests. Video never starts a byte read:
    /// neither the existing image rules nor metadata enum supplies a video policy.
    func beginSelection(kind: SquarePostLocalMediaKind, request: SquarePostLocalMediaPickerRequest) -> SquarePostLocalMediaByteInspection? {
        guard pickerRequest == request, scope == request.scope, let selection else {
            discardedCallbacks += 1; return nil
        }
        pickerRequest = nil; remove()
        selectedKind = kind
        do {
            let id = try selection.append(reference: .init(), kind: kind)
            if kind == .video { state = .videoUnavailable; return nil }
            let inspection = try selection.beginInspection(id)
            activeInspection = inspection.token; state = .loading
            return inspection
        } catch { state = .failed; return nil }
    }
    @discardableResult func complete(_ result: SquarePostLocalMediaImagePreview) -> Bool {
        guard result.evidence.token == activeInspection,
              scope == result.evidence.token.scope, selection?.complete(result.evidence) == true else {
            discardedCallbacks += 1; return false
        }
        image = result; activeInspection = nil; loadTask = nil; state = .imagePreview
        return true
    }
    func fail(_ token: SquarePostLocalMediaInspectionToken, cancelled: Bool = false) {
        guard token == activeInspection else { discardedCallbacks += 1; return }
        if cancelled { _ = selection?.cancelInspection(token) }
        else { _ = selection?.fail(token) }
        activeInspection = nil; loadTask = nil; image = nil; previewRequest = nil
        state = cancelled ? .cancelled : .failed
    }
    func cancelInspection() {
        loadTask?.cancel(); loadTask = nil
        if let activeInspection { _ = selection?.cancelInspection(activeInspection) }
        activeInspection = nil; image = nil; previewRequest = nil; state = .cancelled
    }
    func remove() {
        pickerRequest = nil
        loadTask?.cancel(); loadTask = nil; activeInspection = nil
        _ = selection?.clear(); image = nil; previewRequest = nil; selectedKind = nil; unresolvedSelection = false; state = .empty
    }
    func isCurrentUpload(_ upload: SquarePostLocalMediaImageUpload) -> Bool {
        imageUpload?.reference == upload.reference && scope == upload.scope
    }
    /// Called only after the existing coordinator returned an acknowledgment and
    /// the host rechecked its current account/draft/lane. Applying and consuming
    /// are one main-actor step, so a retired selection or duplicate ACK cannot append.
    @discardableResult func applyUploadAcknowledgment(_ upload: SquarePostLocalMediaImageUpload, apply: () -> Void) -> Bool {
        guard isCurrentUpload(upload) else { return false }
        apply(); clearUploaded(upload); return true
    }
    func clearUploaded(_ upload: SquarePostLocalMediaImageUpload) {
        guard imageUpload?.reference == upload.reference, scope == upload.scope else { return }
        remove()
    }
    func openPreview() { if imageUpload != nil { previewRequest = UUID() } }
    func closePreview() { previewRequest = nil }
    func previewIsCurrent(_ id: UUID) -> Bool { previewRequest == id && imageUpload != nil }
    func invalidate() {
        pickerRequest = nil; remove(); _ = selection?.invalidate()
        selection = nil; scope = nil; state = .expired
    }
}

/// Inline thumbnail then attachment tools, following the Mini composer hierarchy.
/// The enlarged sheet always reads current model pixels; it never retains an old UIImage.
@MainActor struct SquarePostLocalMediaPreview: View {
    let model: SquarePostLocalMediaPresentation
    @Environment(\.locale) private var locale
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private func text(_ chinese: String, _ english: String) -> String { self.chinese ? chinese : english }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnail = model.thumbnail {
                Button { model.openPreview() } label: {
                    Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 160)
                }
                .accessibilityLabel(text("预览已选图片", "Preview selected image"))
                .accessibilityIdentifier("squarePostLocalMedia.preview")
            }
            switch model.state {
            case .loading:
                ProgressView(text("正在读取所选图片", "Reading selected image"))
                Button(text("取消读取", "Cancel loading")) { model.cancelInspection() }
                    .accessibilityIdentifier("squarePostLocalMedia.cancel")
            case .videoUnavailable:
                Label(text("视频暂不可用", "Video unavailable"), systemImage: "video.slash")
                Text(text("视频的上传、解码和大小/时长规则尚未接通。未读取视频文件，也未上传。可以移除后选择图片。",
                          "Video upload, decoding, and size/duration rules are not connected. No video file was read or uploaded. Remove it to choose an image."))
                    .font(.caption).accessibilityIdentifier("squarePostLocalMedia.videoUnavailable")
            case .imagePreview:
                Text(text("仅本地图片预览，尚未上传", "Local image preview; not uploaded"))
                    .font(.caption)
            case .cancelled: Text(text("已取消选择或读取", "Selection or loading cancelled"))
            case .failed: Text(text("无法读取或不支持此媒体。请选择 JPEG 或 PNG 图片，或移除此选择。", "This media could not be read or is unsupported. Choose a JPEG or PNG image, or remove this selection."))
            case .expired: Text(text("上次选择已失效，请重新选择", "Previous selection expired. Choose again."))
            case .empty, .choosing: EmptyView()
            }
            if model.hasSelection {
                Text(text("上传图片或移除本地选择后，才能保存到服务器或继续发布。本地媒体不会随草稿保存。",
                          "Upload the image or remove the local selection before saving to the server or publishing. Local media is not saved with drafts."))
                    .font(.caption).accessibilityIdentifier("squarePostLocalMedia.pendingBoundary")
            }
        }
        .accessibilityIdentifier("squarePostLocalMedia.state")
        .sheet(isPresented: Binding(get: { model.previewRequest != nil }, set: { if !$0 { model.closePreview() } })) {
            if let request = model.previewRequest {
                NavigationStack {
                    Group {
                        if model.previewIsCurrent(request), let thumbnail = model.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit()
                                .accessibilityLabel(text("所选图片的本地缩略预览", "Local thumbnail of the selected image"))
                        } else { Text(text("预览已失效", "Preview expired")) }
                    }.padding().toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(text("关闭", "Close")) { model.closePreview() }
                        }
                    }
                }
            }
        }
    }
}

@MainActor struct SquarePostLocalMediaPickerLabel: View {
    @Environment(\.locale) private var locale
    var body: some View {
        Label(locale.language.languageCode?.identifier == "zh" ? "选择图片或视频" : "Choose image or video",
              systemImage: "photo.on.rectangle")
    }
}
