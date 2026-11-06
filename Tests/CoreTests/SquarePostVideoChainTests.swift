import XCTest
@testable import QuestifyCore

/// U01 video chain: read mapping, review vocabulary, inspection policy, disabled upload, registration body, save/restore.
@MainActor final class SquarePostVideoChainTests: XCTestCase {
    private func policy(video: Bool = true) throws -> SquarePostLocalMediaPolicy {
        try SquarePostLocalMediaPolicy(mimeTypes: video ? [.video: ["video/mp4"]] : [:], maximumItems: 9, maximumImages: 9,
            maximumVideos: 1, allowsMixed: false, maximumImageBytes: 1_000, maximumVideoBytes: video ? 5_000 : nil,
            maximumTotalBytes: 5_000, maximumVideoDurationMilliseconds: video ? 60_000 : nil)  // artificial test values
    }
    private func inspection(bytes: Int64 = 4_000, ms: Int64 = 15_000, mime: String = "video/mp4", track: Bool = true, playable: Bool = true) -> SquarePostVideoInspection {
        .init(byteCount: bytes, mimeType: mime, durationMilliseconds: ms, width: 720, height: 1280, hasVideoTrack: track, isPlayable: playable)
    }

    func testPostReadsRegisteredVideoRowsSeparatelyFromImages() throws {
        let json = #"{"post":{"id":9,"authorId":3,"version":1},"media":[{"id":1,"media_type":"IMAGE","derived_object_key":"https://example.invalid/i.png"},{"id":2,"media_type":"VIDEO","derived_object_key":"https://example.invalid/v.mp4","duration_ms":15000,"width":720,"height":1280,"mime_type":"video/mp4"},{"id":3,"mediaType":"VIDEO","objectKey":"k/3.mp4","reviewState":"REJECTED","reviewReason":"Synthetic reason"},{"id":0,"media_type":"VIDEO","object_key":"bad"}]}"#
        let post = try JSONDecoder().decode(SquarePost.self, from: Data(json.utf8))
        XCTAssertEqual(post.images, ["https://example.invalid/i.png"])
        XCTAssertEqual(post.videos.map(\.id), [2, 3])
        XCTAssertEqual(post.videos[0].durationMilliseconds, 15000)
        XCTAssertEqual(post.videos[0].review, .approved)
        XCTAssertEqual(post.videos[1].source, "k/3.mp4")
        XCTAssertEqual(post.videos[1].review, .rejected(reason: "Synthetic reason"))
        XCTAssertTrue(try JSONDecoder().decode(SquarePost.self, from: Data(#"{"id":4,"memberId":3,"pics":"a.png"}"#.utf8)).videos.isEmpty)
    }

    func testReviewVocabulary() {
        XCTAssertTrue(SquareMediaReviewState(state: "APPROVED", reason: nil).canAttach)
        XCTAssertEqual(SquareMediaReviewState(state: "PENDING", reason: nil), .pending)
        XCTAssertFalse(SquareMediaReviewState(state: "PENDING", reason: nil).canAttach)
        XCTAssertTrue(SquareMediaReviewState(state: "REJECTED", reason: "x").canRequestReview)
        XCTAssertTrue(SquareMediaReviewState(state: "UNAVAILABLE", reason: nil).canRequestReview)
        XCTAssertEqual(SquareMediaReviewState(state: "SOMETHING_NEW", reason: nil), .unknown)
    }

    func testInspectionAgainstInjectedPolicyNeverDefaultsToUnlimited() throws {
        XCTAssertEqual(inspection().rejections(policy: nil), [.policyUnavailable])
        XCTAssertEqual(inspection().rejections(policy: try policy(video: false)), [.policyUnavailable])
        XCTAssertEqual(inspection().rejections(policy: try policy()), [])
        XCTAssertEqual(inspection(bytes: 5_001).rejections(policy: try policy()), [.byteLimit])
        XCTAssertEqual(inspection(ms: 60_001).rejections(policy: try policy()), [.durationLimit])
        XCTAssertEqual(inspection(mime: "video/quicktime", track: false, playable: false).rejections(policy: try policy()), [.mimeNotAllowed, .noVideoTrack, .notPlayable])
    }

    func testUploadStaysUnavailableEvenWithAPolicy() throws {
        XCTAssertEqual(SquarePostVideoUploadAvailability.current(policy: nil), .unavailable(.policyUnavailable))
        XCTAssertEqual(SquarePostVideoUploadAvailability.current(policy: try policy()), .unavailable(.noReviewedVideoUploadEndpoint))
    }

    func testRegistrationBodyMatchesBackendFieldsAndCeiling() throws {
        let registration = try SquarePostVideoRegistration(uploadRequestID: "video-req-0001", objectKey: "community/v.mp4", uploadReceipt: "synthetic-receipt", inspection: inspection())
        XCTAssertEqual(Set(registration.body.keys), ["uploadRequestId", "mediaType", "objectKey", "uploadReceipt", "mimeType", "byteSize", "width", "height", "durationMs"])
        XCTAssertEqual(registration.body["mediaType"] as? String, "VIDEO")
        XCTAssertEqual(SquarePostVideoRegistration.path, "api/v1/community/media/register")
        XCTAssertThrowsError(try SquarePostVideoRegistration(uploadRequestID: "video-req-0001", objectKey: "k", uploadReceipt: "r",
                                                             inspection: inspection(bytes: SquarePostVideoRegistration.serverByteCeiling + 1)))
        XCTAssertThrowsError(try SquarePostVideoRegistration(uploadRequestID: "short", objectKey: "k", uploadReceipt: "r", inspection: inspection()))
    }

    func testDraftSaveRestoreDetectsMissingAndChangedFilesPerAccount() throws {
        let store = SquarePostMediaDraftStore(storage: SquareWorkspaceMemoryStorage())
        let session = try SquareWorkspaceSession(accountID: 7, namespace: "cn", epoch: 1)
        let other = try SquareWorkspaceSession(accountID: 8, namespace: "cn", epoch: 1)
        let a = SquarePostMediaDraftItem(kind: .video, registryID: UUID(), sha256: String(repeating: "a", count: 64), byteCount: 10, mimeType: "video/mp4", width: 1, height: 1, durationMilliseconds: 1000)
        let b = SquarePostMediaDraftItem(kind: .image, registryID: UUID(), sha256: String(repeating: "b", count: 64), byteCount: 5, mimeType: "image/png", width: 1, height: 1, durationMilliseconds: nil)
        let c = SquarePostMediaDraftItem(kind: .image, registryID: UUID(), sha256: String(repeating: "c", count: 64), byteCount: 5, mimeType: "image/png", width: 1, height: 1, durationMilliseconds: nil)
        try store.save([a, b, c], session: session, draftID: "draft-1")
        let files: [UUID: (String, Int64)] = [a.registryID: (a.sha256, 10), b.registryID: (String(repeating: "x", count: 64), 5)]
        let restored = try store.restore(session: session, draftID: "draft-1") { files[$0].map { ($0.0, $0.1) } }
        XCTAssertEqual(restored.map { $0.0.id }, [a.id, b.id, c.id])
        XCTAssertEqual(restored.map { $0.1 }, [.ready, .changed, .missing])
        XCTAssertTrue(try store.restore(session: other, draftID: "draft-1") { _ in nil }.isEmpty)
        XCTAssertThrowsError(try store.save([a, a], session: session, draftID: "draft-1"))
        try store.clear(session: session, draftID: "draft-1")
        XCTAssertTrue(try store.restore(session: session, draftID: "draft-1") { _ in nil }.isEmpty)
    }
}
