import Combine
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Club-post-specific image selection seam.
/// Supplies sanitized `RetainedSelectedImage` bytes from the native picker without granting
/// upload or post-publication permissions on its own.
@MainActor
protocol ClubPostImagePicking: AnyObject {
    var canSelect: Bool { get }
    func select() async throws -> RetainedSelectedImage?
    func cancel()
}

@MainActor
final class ClubPostDisabledImagePicker: ClubPostImagePicking {
    var canSelect: Bool { false }
    func select() async throws -> RetainedSelectedImage? { nil }
    func cancel() {}
}

@MainActor
final class ClubPostNativeImagePicker: ClubPostImagePicking {
    private let picker: RetainedNativeImagePicker
    private let permitted: () -> Bool

    init(host: RetainedImagePickerHost, permitted: @escaping () -> Bool) {
        self.permitted = permitted
        self.picker = host.makePicker(selectionApproval: permitted)
    }

    var canSelect: Bool { permitted() }

    func select() async throws -> RetainedSelectedImage? {
        guard permitted() else { return nil }
        return try await picker.select()
    }

    func cancel() {
        picker.cancel()
    }
}

@MainActor
struct ClubPostImagePickerContext {
    let makePickerForClub: (Int, Int?) -> any ClubPostImagePicking
    let makeUploaderForClub: (Int, Int?) -> any ClubPostImageUploading
    let currentUploadContext: (Int, Int?) -> ClubPostImageUploadContext?

    init(
        makePicker: @escaping () -> any ClubPostImagePicking,
        uploader: any ClubPostImageUploading,
        currentUploadContext: @escaping (Int, Int?) -> ClubPostImageUploadContext?
    ) {
        self.makePickerForClub = { _, _ in makePicker() }
        self.makeUploaderForClub = { _, _ in uploader }
        self.currentUploadContext = currentUploadContext
    }

    init(
        makePickerForClub: @escaping (Int, Int?) -> any ClubPostImagePicking,
        makeUploaderForClub: @escaping (Int, Int?) -> any ClubPostImageUploading,
        currentUploadContext: @escaping (Int, Int?) -> ClubPostImageUploadContext?
    ) {
        self.makePickerForClub = makePickerForClub
        self.makeUploaderForClub = makeUploaderForClub
        self.currentUploadContext = currentUploadContext
    }

    static let disabled = ClubPostImagePickerContext(
        makePicker: { ClubPostDisabledImagePicker() },
        uploader: ClubPostImageDisabledUploader(),
        currentUploadContext: { _, _ in nil }
    )
}

/// Coordinates native image selection, local candidate preview/deletion, and approved upload
/// for `ClubCommunityComposer` without ever mutating composer text or auto-submitting the post.
@MainActor
final class ClubPostImageComposerBridge: ObservableObject {
    private let picker: any ClubPostImagePicking
    private let clubID: Int
    private let postID: Int?
    private let resolveContext: (Int, Int?) -> ClubPostImageUploadContext?
    let draft: ClubPostImageDraftController

    @Published private(set) var isSelecting = false
    @Published private(set) var previewingCandidate: RetainedSelectedImage?
    private var generation: UInt64 = 0
    private var cancellable: AnyCancellable?

    init(
        context: ClubPostImagePickerContext,
        clubID: Int,
        postID: Int?
    ) {
        self.picker = context.makePickerForClub(clubID, postID)
        self.clubID = clubID
        self.postID = postID
        self.resolveContext = context.currentUploadContext
        self.draft = ClubPostImageDraftController(
            uploader: context.makeUploaderForClub(clubID, postID),
            currentContext: { context.currentUploadContext(clubID, postID) }
        )
        self.cancellable = draft.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var canSelectImage: Bool {
        guard let uploadContext = resolveContext(clubID, postID) else { return false }
        return picker.canSelect || draft.validateCurrentContext() == uploadContext && picker.canSelect
    }

    var isBusy: Bool {
        isSelecting || draft.isUploading
    }

    func bind(initialReferences: [String]) {
        let current = resolveContext(clubID, postID)
        draft.bind(context: current, initialReferences: initialReferences)
    }

    /// Selects an image from the native picker and stages it into `draft`.
    /// Returning from the picker or preview never alters text content and never auto-submits.
    @discardableResult
    func selectAndStageImage() async -> [String] {
        guard !isBusy,
              let capturedContext = resolveContext(clubID, postID),
              picker.canSelect,
              draft.canAddMoreImages else {
            return draft.uploadedReferences
        }
        draft.bind(context: capturedContext, initialReferences: draft.uploadedReferences)
        generation &+= 1
        let ticket = generation
        isSelecting = true
        defer {
            if ticket == generation {
                isSelecting = false
            }
        }
        do {
            guard let selected = try await picker.select() else {
                return draft.uploadedReferences
            }
            guard !Task.isCancelled,
                  ticket == generation,
                  resolveContext(clubID, postID) == capturedContext else {
                if resolveContext(clubID, postID) != capturedContext {
                    invalidate()
                }
                return draft.uploadedReferences
            }
            _ = await draft.stageSelectedImage(selected)
            return draft.uploadedReferences
        } catch {
            if resolveContext(clubID, postID) != capturedContext {
                invalidate()
            }
            return draft.uploadedReferences
        }
    }

    @discardableResult
    func selectAndReplaceUploadedReference(at index: Int) async -> [String] {
        guard !isBusy,
              let capturedContext = resolveContext(clubID, postID),
              picker.canSelect,
              draft.uploadedReferences.indices.contains(index) else {
            return draft.uploadedReferences
        }
        draft.bind(context: capturedContext, initialReferences: draft.uploadedReferences)
        generation &+= 1
        let ticket = generation
        isSelecting = true
        defer {
            if ticket == generation {
                isSelecting = false
            }
        }
        do {
            guard let selected = try await picker.select() else {
                return draft.uploadedReferences
            }
            guard !Task.isCancelled,
                  ticket == generation,
                  resolveContext(clubID, postID) == capturedContext else {
                if resolveContext(clubID, postID) != capturedContext {
                    invalidate()
                }
                return draft.uploadedReferences
            }
            _ = await draft.replaceUploadedReference(at: index, with: selected)
            return draft.uploadedReferences
        } catch {
            if resolveContext(clubID, postID) != capturedContext {
                invalidate()
            }
            return draft.uploadedReferences
        }
    }

    func selectAndReplaceLocalCandidate(id: UUID) async {
        guard !isBusy,
              let capturedContext = resolveContext(clubID, postID),
              picker.canSelect,
              draft.localCandidates.contains(where: { $0.id == id }) else {
            return
        }
        draft.bind(context: capturedContext, initialReferences: draft.uploadedReferences)
        generation &+= 1
        let ticket = generation
        isSelecting = true
        defer {
            if ticket == generation {
                isSelecting = false
            }
        }
        do {
            guard let selected = try await picker.select() else { return }
            guard !Task.isCancelled,
                  ticket == generation,
                  resolveContext(clubID, postID) == capturedContext else {
                if resolveContext(clubID, postID) != capturedContext {
                    invalidate()
                }
                return
            }
            if previewingCandidate?.id == id {
                previewingCandidate = selected
            }
            _ = draft.replaceLocalCandidate(id: id, with: selected)
        } catch {
            if resolveContext(clubID, postID) != capturedContext {
                invalidate()
            }
        }
    }

    @discardableResult
    func removeUploadedReference(at index: Int) -> [String] {
        if draft.uploadedReferences.indices.contains(index) {
            let removed = draft.uploadedReferences[index]
            if let preview = draft.previewsByReference[removed], previewingCandidate?.id == preview.id {
                previewingCandidate = nil
            }
        }
        draft.removeUploadedReference(at: index)
        return draft.uploadedReferences
    }

    func removeLocalCandidate(id: UUID) {
        if previewingCandidate?.id == id {
            previewingCandidate = nil
        }
        draft.removeLocalCandidate(id: id)
    }

    func openPreview(_ candidate: RetainedSelectedImage) {
        previewingCandidate = candidate
    }

    func openUploadedPreview(for reference: String) {
        guard let candidate = draft.previewsByReference[reference] else { return }
        previewingCandidate = candidate
    }

    func closePreview() {
        previewingCandidate = nil
    }

    /// Cancels an active picker presentation or in-flight upload while preserving existing draft state.
    func cancelActiveSelectionOrUpload() {
        generation &+= 1
        isSelecting = false
        picker.cancel()
        draft.cancelCurrentUpload()
    }

    func invalidate() {
        generation &+= 1
        isSelecting = false
        previewingCandidate = nil
        picker.cancel()
        draft.invalidate()
    }
}

@MainActor
struct ClubPostImageSectionView: View {
    @ObservedObject var bridge: ClubPostImageComposerBridge
    @Binding var images: [String]
    @Binding var uploading: Bool
    @Binding var notice: String?

    var body: some View {
        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
            HStack(spacing: 8) {
                #if canImport(UIKit)
                if let localPreview = bridge.draft.previewsByReference[image],
                   let uiImage = UIImage(data: localPreview.jpeg) {
                    Button {
                        bridge.openUploadedPreview(for: image)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("club.community.uploadedImagePreview.\(index)")
                }
                #endif
                Text(verbatim: image).lineLimit(1)
                Spacer()
                if bridge.canSelectImage {
                    Button {
                        uploading = true
                        Task {
                            images = await bridge.selectAndReplaceUploadedReference(at: index)
                            if let key = bridge.draft.statusKey, key == "club.community.actionUnavailable" {
                                notice = key
                            }
                            uploading = bridge.isBusy
                        }
                    } label: {
                        Label("club.community.replaceImage", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(bridge.isBusy || uploading)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("club.community.replaceImage.\(index)")
                }
                Button {
                    images = bridge.removeUploadedReference(at: index)
                } label: {
                    Label("club.community.removeImage", systemImage: "xmark.circle")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("club.community.removeImage.\(index)")
            }
        }

        ForEach(bridge.draft.localCandidates, id: \.id) { candidate in
            HStack(spacing: 8) {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: candidate.jpeg) {
                    Button {
                        bridge.openPreview(candidate)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("club.community.localImagePreview.\(candidate.id.uuidString)")
                }
                #endif
                Text("\(candidate.width)×\(candidate.height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if bridge.canSelectImage {
                    Button {
                        Task {
                            await bridge.selectAndReplaceLocalCandidate(id: candidate.id)
                            uploading = bridge.isBusy
                        }
                    } label: {
                        Label("club.community.replaceImage", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(bridge.isBusy || uploading)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("club.community.replaceLocalImage.\(candidate.id.uuidString)")
                }
                Button {
                    bridge.removeLocalCandidate(id: candidate.id)
                } label: {
                    Label("club.community.removeImage", systemImage: "xmark.circle")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("club.community.removeLocalImage.\(candidate.id.uuidString)")
            }
        }

        if let statusKey = bridge.draft.statusKey {
            Text(LocalizedStringKey(statusKey))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("club.community.imageStatus")
        }

        if bridge.isBusy || uploading {
            Button("club.community.cancelImageUpload", role: .cancel) {
                bridge.cancelActiveSelectionOrUpload()
                uploading = false
            }
            .accessibilityIdentifier("club.community.cancelImageUpload")
        }

        if bridge.canSelectImage {
            Button("club.community.selectImage") {
                uploading = true
                Task {
                    images = await bridge.selectAndStageImage()
                    if let key = bridge.draft.statusKey, key == "club.community.actionUnavailable" {
                        notice = key
                    }
                    uploading = bridge.isBusy
                }
            }
            .disabled(!bridge.draft.canAddMoreImages || bridge.isBusy || uploading)
            .accessibilityIdentifier("club.community.selectImage")
        } else {
            Text("club.community.imagesOff")
        }
        Color.clear
            .frame(height: 0)
            .sheet(
                isPresented: Binding(
                    get: { bridge.previewingCandidate != nil },
                    set: { if !$0 { bridge.closePreview() } }
                )
            ) {
                if let candidate = bridge.previewingCandidate {
                    ClubPostImagePreviewSheet(candidate: candidate) {
                        bridge.closePreview()
                    }
                }
            }
    }
}

@MainActor
private struct ClubPostImagePreviewSheet: View {
    let candidate: RetainedSelectedImage
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: candidate.jpeg) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .accessibilityIdentifier("club.community.imagePreviewSheet.image")
                }
                #endif
                Text("\(candidate.width)×\(candidate.height)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle(Text("club.community.imagePreview"))
            .toolbar {
                Button("club.community.closePreview") {
                    onClose()
                }
                .accessibilityIdentifier("club.community.imagePreviewSheet.close")
            }
        }
    }
}
