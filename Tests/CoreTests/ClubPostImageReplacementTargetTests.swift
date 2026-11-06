import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class TargetBoundClubUploader: ClubPostImageUploading {
    var started: (() -> Void)?
    private var continuation: CheckedContinuation<ClubPostUploadedImage, Error>?
    private var result: ClubPostUploadedImage?
    func isConfigured(for context: ClubPostImageUploadContext) -> Bool { true }
    func permitsPicker(for context: ClubPostImageUploadContext) -> Bool { false }
    func permittedReference(_ uploaded: ClubPostUploadedImage, for context: ClubPostImageUploadContext) -> String? {
        uploaded.context == context ? uploaded.reference : nil
    }
    func upload(_ image: RetainedSelectedImage, attemptID: UUID, context: ClubPostImageUploadContext) async throws -> ClubPostUploadedImage {
        result = .init(attemptID: attemptID, context: context, reference: "https://cdn.example.com/replacement.jpg", image: image)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation; started?()
        }
    }
    func finish() {
        guard let continuation, let result else { preconditionFailure("Upload not started") }
        self.continuation = nil; continuation.resume(returning: result)
    }
}
@MainActor final class ClubPostImageReplacementTargetTests: XCTestCase {
    private let a = "https://cdn.example.com/a.jpg"
    private let b = "https://cdn.example.com/b.jpg"
    private let c = "https://cdn.example.com/c.jpg"
    private func run(initial: [String], replacing: Int, remove: Int?) async throws {
        let uploader = TargetBoundClubUploader()
        let context = try ClubPostImageUploadContext(accountID: 7, epoch: 1, namespace: "replacement-test", clubID: 3)
        let image = try RetainedSelectedImage(jpeg: Data([255,216,255,224,1,255,217]), width: 120, height: 90)
        let draft = ClubPostImageDraftController(uploader: uploader, currentContext: { context })
        draft.bind(context: context, initialReferences: initial)
        var task: Task<Bool, Never>?
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            uploader.started = { ready.resume() }
            task = Task { await draft.replaceUploadedReference(at: replacing, with: image) }
        }
        XCTAssertTrue(draft.isUploading)
        if let remove { draft.removeUploadedReference(at: remove) }
        let retained = draft.uploadedReferences
        uploader.finish()
        let operation = try XCTUnwrap(task)
        let accepted = await operation.value
        if let remove, initial.indices.contains(remove) {
            XCTAssertFalse(accepted)
            XCTAssertEqual(draft.uploadedReferences, retained)
            XCTAssertEqual(draft.statusKey, "club.community.actionUnavailable")
            XCTAssertTrue(draft.previewsByReference.isEmpty)
        } else {
            XCTAssertTrue(accepted)
            var expected = initial; expected[replacing] = "https://cdn.example.com/replacement.jpg"
            XCTAssertEqual(draft.uploadedReferences, expected)
            XCTAssertEqual(draft.previewsByReference[expected[replacing]], image)
            XCTAssertNil(draft.statusKey)
        }
        XCTAssertFalse(draft.isUploading); XCTAssertFalse(draft.didAutoSubmit)
    }
    func testRemovingReplacementTargetDoesNotOverwriteNextAttachment() async throws {
        try await run(initial: [a,b,c], replacing: 1, remove: 1)
    }
    func testRemovingEarlierAttachmentDoesNotOverwriteShiftedAttachment() async throws {
        try await run(initial: [a,b,c], replacing: 1, remove: 0)
    }
    func testDuplicateReferenceStillCannotProveSameOriginalItem() async throws {
        try await run(initial: [a,a,b], replacing: 0, remove: 0)
    }
    func testUnchangedTargetReplacesNormally() async throws {
        try await run(initial: [a,b,c], replacing: 1, remove: nil)
    }
    func testInvalidRemovalDoesNotRetireValidReplacement() async throws {
        try await run(initial: [a,b,c], replacing: 1, remove: 99)
    }
    func testAnyRemovalRetiresCapturedPositionalSnapshotWithoutRestoringIt() async throws {
        try await run(initial: [a,b,c], replacing: 0, remove: 2)
    }
}
