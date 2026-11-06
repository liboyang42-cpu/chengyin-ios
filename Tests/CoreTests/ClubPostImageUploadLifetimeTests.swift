import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class DeferredClubImageUploader: ClubPostImageUploading {
    struct Call {
        let image: RetainedSelectedImage
        let attempt: UUID
        let context: ClubPostImageUploadContext
        let continuation: CheckedContinuation<ClubPostUploadedImage, Error>
    }
    var calls: [Call] = []
    private var waiter: (Int, CheckedContinuation<Void, Never>)?
    func isConfigured(for context: ClubPostImageUploadContext) -> Bool { true }
    func permitsPicker(for context: ClubPostImageUploadContext) -> Bool { false }
    func permittedReference(_ uploaded: ClubPostUploadedImage, for context: ClubPostImageUploadContext) -> String? {
        uploaded.context == context ? uploaded.reference : nil
    }
    func upload(_ image: RetainedSelectedImage, attemptID: UUID, context: ClubPostImageUploadContext) async throws -> ClubPostUploadedImage {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(.init(image: image, attempt: attemptID, context: context, continuation: continuation))
            if let (count, continuation) = waiter, calls.count >= count { waiter = nil; continuation.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }
    func finish(_ index: Int) {
        let call = calls[index]
        call.continuation.resume(returning: .init(attemptID: call.attempt, context: call.context,
            reference: "https://cdn.example.com/image-\(index).jpg", image: call.image))
    }
}
@MainActor final class ClubPostImageUploadLifetimeTests: XCTestCase {
    private func context(_ account: Int = 7) throws -> ClubPostImageUploadContext {
        try .init(accountID: account, epoch: UInt64(account), namespace: "image-tests", clubID: 3)
    }
    private func image() throws -> RetainedSelectedImage {
        try .init(jpeg: Data([255,216,255,224,1,255,217]), width: 120, height: 90)
    }
    func testCancelledOldStageDoesNotClearNewUploadBusyState() async throws {
        let uploader = DeferredClubImageUploader(), context = try context(), image = try image()
        let draft = ClubPostImageDraftController(uploader: uploader, currentContext: { context })
        draft.bind(context: context)
        let first = Task { await draft.stageSelectedImage(image) }
        await uploader.waitForCalls(1)
        draft.cancelCurrentUpload()
        let second = Task { await draft.stageSelectedImage(image) }
        await uploader.waitForCalls(2)
        uploader.finish(0)
        let obsolete = await first.value
        XCTAssertFalse(obsolete); XCTAssertTrue(draft.isUploading); XCTAssertNil(draft.statusKey)
        XCTAssertTrue(draft.uploadedReferences.isEmpty)
        uploader.finish(1)
        let accepted = await second.value
        XCTAssertTrue(accepted); XCTAssertFalse(draft.isUploading)
        XCTAssertEqual(draft.uploadedReferences, ["https://cdn.example.com/image-1.jpg"])
    }
    func testCancelledOldStagePreservesExplicitCancellationMessage() async throws {
        let uploader = DeferredClubImageUploader(), context = try context(), image = try image()
        let draft = ClubPostImageDraftController(uploader: uploader, currentContext: { context })
        draft.bind(context: context)
        let task = Task { await draft.stageSelectedImage(image) }
        await uploader.waitForCalls(1); draft.cancelCurrentUpload(); uploader.finish(0)
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertEqual(draft.statusKey, "club.community.imageUploadCancelled")
        XCTAssertTrue(draft.uploadedReferences.isEmpty)
    }
    func testOldAccountStageCannotInvalidateNewAccountsDraft() async throws {
        try await checkAccountReplacement(replacing: false)
    }
    func testOldAccountReplacementCannotInvalidateNewAccountsDraft() async throws {
        try await checkAccountReplacement(replacing: true)
    }
    private func checkAccountReplacement(replacing: Bool) async throws {
        let uploader = DeferredClubImageUploader(), image = try image()
        var current = try context()
        let draft = ClubPostImageDraftController(uploader: uploader, currentContext: { current })
        draft.bind(context: current, initialReferences: ["https://cdn.example.com/old.jpg"])
        let old = Task {
            if replacing { return await draft.replaceUploadedReference(at: 0, with: image) }
            return await draft.stageSelectedImage(image)
        }
        await uploader.waitForCalls(1)
        current = try context(8)
        draft.bind(context: current, initialReferences: ["https://cdn.example.com/new-owner.jpg"])
        let fresh = Task { await draft.stageSelectedImage(image) }
        await uploader.waitForCalls(2)
        uploader.finish(0)
        let stale = await old.value
        XCTAssertFalse(stale)
        XCTAssertTrue(draft.isUploading); XCTAssertNil(draft.statusKey)
        XCTAssertEqual(draft.uploadedReferences, ["https://cdn.example.com/new-owner.jpg"])
        uploader.finish(1)
        let accepted = await fresh.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(draft.uploadedReferences, ["https://cdn.example.com/new-owner.jpg", "https://cdn.example.com/image-1.jpg"])
        XCTAssertEqual(draft.previewsByReference["https://cdn.example.com/image-1.jpg"], image)
        XCTAssertFalse(draft.didAutoSubmit)
    }
}
