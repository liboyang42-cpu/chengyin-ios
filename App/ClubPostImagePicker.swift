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
    let makePicker: () -> any ClubPostImagePicking
    let uploader: any ClubPostImageUploading
    let currentUploadContext: (Int, Int?) -> ClubPostImageUploadContext?

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
        self.picker = context.makePicker()
        self.clubID = clubID
        self.postID = postID
        self.resolveContext = context.currentUploadContext
        self.draft = ClubPostImageDraftController(
            uploader: context.uploader,
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
    func removeUploadedReference(at index: Int) -> [String] {
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

    func closePreview() {
        previewingCandidate = nil
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
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                #endif
                Text(verbatim: image).lineLimit(1)
                Spacer()
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
    }
}
