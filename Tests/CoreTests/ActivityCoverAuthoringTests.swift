import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class CoverJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var fails = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if fails { throw APIError.malformedResponse }; return records[ownerKey + targetKey]
    }
    func write(_ record: OperationPendingRecord) throws {
        if fails { throw APIError.malformedResponse }
        let key = record.ownerKey + record.targetKey
        guard records[key] == nil || records[key]?.operationID == record.operationID else { throw APIError.invalidRequest }
        records[key] = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        guard !fails, records[record.ownerKey + record.targetKey] == record else { throw APIError.invalidRequest }
        records[record.ownerKey + record.targetKey] = nil
    }
}
@MainActor private final class CoverWire: HTTPTransport {
    var requests: [URLRequest] = []
    var bytes = Data(#"{"code":200,"url":"https://images.example.test/activity.jpg?version=original"}"#.utf8)
    var status = 200
    var fail = false
    var held = false
    var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if held { return try await withCheckedThrowingContinuation { continuation = $0 } }
        if fail { throw URLError(.networkConnectionLost) }; return (bytes, status)
    }
}
@MainActor private final class CoverHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://cover.example.test")!)
    let session = PublishingSession(namespace: "cover-synthetic", accountID: 7, epoch: UUID(), role: "club", region: .china)
    var credential: PublishingCredentials?
    var grant: ActivityCoverApproval?
    let wire = CoverWire(), journal = CoverJournal()
    lazy var service = makeService()
    init(approved: Bool = true) throws {
        credential = try .init(session: session, token: "synthetic-cover-token")
        if approved { grant = try .init(endpoint: .init(baseURL: configuration.baseURL, namespace: session.namespace, accountID: session.accountID, paths: [ActivityCoverService.path]), revision: UUID(), approvedOrigins: ["https://images.example.test"], nativePicker: true) }
    }
    func makeService() -> ActivityCoverService {
        ActivityCoverService(configuration: configuration, transport: wire, approval: grant, currentApproval: { [weak self] in self?.grant }, credentials: { [weak self] in self?.credential }, journal: journal)
    }
    func image(width: Int = 160, height: Int = 90) throws -> RetainedSelectedImage { try .init(jpeg: Data([255,216,255,224,7,255,217]), width: width, height: height) }
    func review(target: ActivityCoverTarget = .existing(41)) throws -> ActivityCoverReview { try service.prepare(image(), target: target, session: session) }
}

@MainActor final class ActivityCoverAuthoringTests: XCTestCase {
    func testDefaultNilApprovalCannotPrepareOrEnablePicker() throws {
        let h = try CoverHarness(approved: false)
        XCTAssertFalse(h.service.isCurrent(h.session)); XCTAssertFalse(h.service.permitsPicker(h.session))
        XCTAssertThrowsError(try h.review()); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testApprovalCannotReuseCreateOrTopicPath() throws {
        let h = try CoverHarness()
        XCTAssertThrowsError(try ActivityCoverApproval(endpoint: .init(baseURL: h.configuration.baseURL, namespace: h.session.namespace, accountID: 7, paths: ["api/activity/create"]), revision: UUID(), approvedOrigins: ["https://images.example.test"]))
    }
    func testExactAspectAndPositiveExistingTargetRequired() throws {
        let h = try CoverHarness()
        XCTAssertThrowsError(try h.service.prepare(h.image(width: 100, height: 100), target: .existing(41), session: h.session))
        XCTAssertThrowsError(try h.review(target: .existing(0))); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testExplicitUploadHasExactEndpointMultipartAndLeavesParentUnchangedUntilApply() async throws {
        let h = try CoverHarness(), review = try h.review()
        XCTAssertTrue(h.wire.requests.isEmpty)
        let receipt = try await h.service.upload(review, current: { true })
        let request = try XCTUnwrap(h.wire.requests.first)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(request.url?.path, "/api/common/uploadOSS")
        XCTAssertTrue(ActivityCoverWire.accepts(request, configuration: h.configuration))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-cover-token")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: Data("image_16_9".utf8))); XCTAssertNotNil(body.range(of: Data("name=\"file\"".utf8)))
        var parent = "original"
        XCTAssertEqual(parent, "original"); XCTAssertEqual(try h.service.pending(target: .existing(41), session: h.session)?.acknowledgedSteps, 1)
        XCTAssertTrue(h.service.apply(receipt, current: { true }, consume: { parent = $0; return true }))
        XCTAssertEqual(parent, receipt.reference); XCTAssertNil(try h.service.pending(target: .existing(41), session: h.session))
        XCTAssertFalse(h.service.apply(receipt, current: { true }, consume: { _ in XCTFail("One use"); return true }))
    }
    func testKnownAcknowledgementCanBeExplicitlyDiscardedWithoutApplying() async throws {
        let h = try CoverHarness(); let receipt = try await h.service.upload(h.review(), current: { true })
        XCTAssertTrue(h.service.discard(receipt, current: { true })); XCTAssertNil(try h.service.pending(target: .existing(41), session: h.session))
        XCTAssertFalse(h.service.discard(receipt, current: { true })); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testDefiniteRejectionAllowsOnlyNewExplicitReviewRetry() async throws {
        let h = try CoverHarness(); h.wire.bytes = Data(#"{"code":422,"msg":"Synthetic rejected"}"#.utf8)
        let review = try h.review()
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() }
        catch { XCTAssertEqual(error as? ActivityCoverFailure, .rejected("Synthetic rejected")) }
        XCTAssertNil(try h.service.pending(target: .existing(41), session: h.session)); XCTAssertEqual(h.wire.requests.count, 1)
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch {}
        XCTAssertEqual(h.wire.requests.count, 1)
        let fresh = try h.review(); XCTAssertNotEqual(fresh.id, review.id)
        h.wire.bytes = Data(#"{"code":200,"url":"https://images.example.test/new.jpg"}"#.utf8)
        _ = try await h.service.upload(fresh, current: { true }); XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testUnknownNetworkResultPersistsOriginalAttemptAndCannotRetry() async throws {
        let h = try CoverHarness(); h.wire.fail = true; let review = try h.review()
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch { XCTAssertEqual(error as? ActivityCoverFailure, .unknown) }
        XCTAssertEqual(try h.service.pending(target: .existing(41), session: h.session)?.operationID, review.id)
        XCTAssertThrowsError(try h.review()); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testNewDraftRecreationCannotBypassUnknownReplayLock() async throws {
        let h = try CoverHarness(); h.wire.fail = true; let review = try h.review(target: .newDraft(UUID()))
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch {}
        let reconstructed = h.makeService()
        XCTAssertThrowsError(try reconstructed.prepare(h.image(), target: .newDraft(UUID()), session: h.session))
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testSecondOwnerPreparedBeforeUnknownCannotDispatchThroughSharedJournal() async throws {
        let h = try CoverHarness(), second = h.makeService(), a = try h.review()
        let b = try second.prepare(h.image(), target: .existing(41), session: h.session); h.wire.fail = true
        do { _ = try await h.service.upload(a, current: { true }); XCTFail() } catch {}
        do { _ = try await second.upload(b, current: { true }); XCTFail() } catch { XCTAssertEqual(error as? ActivityCoverFailure, .locked) }
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testJournalFailureBlocksDispatch() async throws {
        let h = try CoverHarness(), review = try h.review(); h.journal.fails = true
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testStaleBeforeDispatchAndCancelledReviewCannotSend() async throws {
        let h = try CoverHarness(), review = try h.review()
        do { _ = try await h.service.upload(review, current: { false }); XCTFail() } catch {}
        h.service.cancel(review)
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testLateReplyAfterOwnerLeavesRemainsUnknownAndNeverMintsReceipt() async throws {
        let h = try CoverHarness(), review = try h.review(); h.wire.held = true; var current = true
        let task = Task { try await h.service.upload(review, current: { current }) }
        while h.wire.continuation == nil { await Task.yield() }; current = false
        h.wire.continuation?.resume(returning: (h.wire.bytes, 200)); h.wire.continuation = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? ActivityCoverFailure, .unknown) }
        XCTAssertEqual(try h.service.pending(target: review.target, session: h.session)?.acknowledgedSteps, 0)
    }
    func testRevokedOrReplacedApprovalCannotSendPreparedReview() async throws {
        let h = try CoverHarness(), review = try h.review(); h.grant = nil
        do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testInvalidResponseOrUnapprovedOriginRemainsUnknown() async throws {
        for body in [#"{"code":200,"url":"http://images.example.test/a.jpg"}"#, #"{"code":200,"url":"https://other.example.test/a.jpg"}"#, #"{"code":true,"url":"https://images.example.test/a.jpg"}"#, #"{"code":200}"#] {
            let h = try CoverHarness(); h.wire.bytes = Data(body.utf8); let review = try h.review()
            do { _ = try await h.service.upload(review, current: { true }); XCTFail() } catch { XCTAssertEqual(error as? ActivityCoverFailure, .unknown) }
            XCTAssertNotNil(try h.service.pending(target: review.target, session: h.session))
        }
    }
    func testStaleOrRefusedApplyCannotClearAcknowledgedReceipt() async throws {
        let h = try CoverHarness(); let receipt = try await h.service.upload(h.review(), current: { true })
        XCTAssertFalse(h.service.apply(receipt, current: { false }, consume: { _ in XCTFail(); return true }))
        XCTAssertFalse(h.service.apply(receipt, current: { true }, consume: { _ in false }))
        XCTAssertEqual(try h.service.pending(target: receipt.review.target, session: h.session)?.acknowledgedSteps, 1)
    }
    func testWireRejectsOtherPathExtraQueryOrWrongBusinessType() async throws {
        let h = try CoverHarness(); _ = try await h.service.upload(h.review(), current: { true })
        var request = try XCTUnwrap(h.wire.requests.first)
        request.url = URL(string: "https://cover.example.test/api/common/uploadOSS?x=1")
        XCTAssertFalse(ActivityCoverWire.accepts(request, configuration: h.configuration))
        request = try XCTUnwrap(h.wire.requests.first); request.httpMethod = "GET"
        XCTAssertFalse(ActivityCoverWire.accepts(request, configuration: h.configuration))
        request = try XCTUnwrap(h.wire.requests.first)
        let body = try XCTUnwrap(request.httpBody); let range = try XCTUnwrap(body.range(of: Data("image_16_9".utf8)))
        request.httpBody?.replaceSubrange(range, with: Data("image_3_4".utf8))
        XCTAssertFalse(ActivityCoverWire.accepts(request, configuration: h.configuration))
    }
}


extension ActivityCoverAuthoringTests {
    func testRemotePreviewRequiresExactApprovedOriginAndCurrentIndependentApproval() throws {
        let h = try CoverHarness(), accepted = "https://images.example.test/a.jpg?version=original"
        XCTAssertTrue(h.service.permitsPreview(accepted, session: h.session))
        for reference in ["https://other.example.test/a.jpg", "http://images.example.test/a.jpg", "https://images.example.test.evil.invalid/a.jpg", "https://name:password@images.example.test/a.jpg", "https://images.example.test/has space.jpg"] {
            XCTAssertFalse(h.service.permitsPreview(reference, session: h.session), reference)
        }
        h.grant = nil; XCTAssertFalse(h.service.permitsPreview(accepted, session: h.session))
        let disabled = try CoverHarness(approved: false)
        XCTAssertFalse(disabled.service.permitsPreview(accepted, session: disabled.session))
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertTrue(disabled.wire.requests.isEmpty)
    }
}
