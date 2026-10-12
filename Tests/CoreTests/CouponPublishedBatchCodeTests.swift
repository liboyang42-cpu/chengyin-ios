import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class CouponPublishedBatchCodeTests: XCTestCase {
    private func rows(_ codeField: String = "") throws -> [CouponDefinition] {
        let suffix = codeField.isEmpty ? "" : "," + codeField
        let data = Data(("{\"code\":200,\"data\":[{\"id\":710,\"name\":\"Synthetic batch\",\"status\":1" + suffix + "}]}").utf8)
        return try CouponManagementContract.decodePublished(data, status: 200)
    }
    func testMissingNullBlankAndSourcePlaceholderKeepLegacyRowValidWithoutBatchCode() throws {
        for field in ["", #""code":null"#, #""code":"""#, #""code":"  \t\n ""#, #""code":"—""#] {
            let decoded = try rows(field)
            XCTAssertEqual(decoded.count, 1); XCTAssertEqual(decoded[0].id.value, 710)
            XCTAssertEqual(decoded[0].name, "Synthetic batch"); XCTAssertNil(decoded[0].publishedBatchCode)
        }
        let old = try CouponManagementContract.decodePublished(CouponManagementSyntheticFixtures.published, status: 200)
        XCTAssertEqual(old.count, 3); XCTAssertTrue(old.allSatisfy { $0.publishedBatchCode == nil })
    }
    func testBatchReferencePreservesExactStringBytesAndLeadingZeros() throws {
        for raw in ["000012", "Batch-ABc", "  000012  ", "批次-A01"] {
            let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": [["id": 710, "code": raw]]])
            let value = try XCTUnwrap(CouponManagementContract.decodePublished(data, status: 200).first?.publishedBatchCode)
            XCTAssertTrue(value.utf8.elementsEqual(raw.utf8))
        }
    }
    func testNonStringBatchCodeCannotMasqueradeAsMissingOrAReference() {
        for invalid in ["1", "true", "false", "[]", "{}"] {
            XCTAssertThrowsError(try rows("\"code\":" + invalid)) { error in
                XCTAssertEqual(error as? CouponManagementError, .malformed)
            }
        }
    }
    func testHistoryIDTokenAndCouponCodeAliasAreNeverUsedAsBatchReference() throws {
        let value = try XCTUnwrap(rows(#""couponHistoryId":999,"couponCode":"legacy","token":"synthetic-token","qrcodeUrl":"https://example.test/qr""#).first)
        XCTAssertNil(value.publishedBatchCode)
    }
    func testBatchReferenceDoesNotChangePublishedListOrMutationRequestShapes() throws {
        let published = CouponManagementContract.published()
        XCTAssertFalse(published.mutates)
        XCTAssertEqual(published.path, "/api/coupon/mypublishlist")
        XCTAssertEqual(published.body, .multipart(["scope": "MERCHANT"]))
        _ = try rows(#""code":"BATCH-710""#)
        let publish = try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft())
        guard case .json(let data) = publish.body else { return XCTFail("Expected existing JSON body") }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["code"]); XCTAssertNil(object["publishedBatchCode"])
        let stop = CouponManagementContract.stop(try CouponDefinitionID(710))
        XCTAssertEqual(stop.body, .multipart(["couponId": "710", "scope": "MERCHANT"]))
    }
    func testStoppedBatchReferenceRemainsMetadataWithoutChangingStatus() throws {
        let data = Data(#"{"code":200,"data":[{"id":710,"status":4,"code":"STOPPED-BATCH"}]}"#.utf8)
        let value = try XCTUnwrap(CouponManagementContract.decodePublished(data, status: 200).first)
        XCTAssertEqual(value.publishedBatchCode, "STOPPED-BATCH"); XCTAssertEqual(value.state, .stopped)
        XCTAssertFalse(value.state.canStop)
    }
    func testExistingCoordinatorReadsReferenceAndClearsItOnSignOut() async throws {
        var current: CouponManagementSession? = try .init(accountID: 1, namespace: "synthetic", epoch: 1, authorizationRevision: "scope-A")
        let wire = PublishedBatchReadWire(), locks = PublishedBatchNoLocks()
        let core = CouponManagementCoordinator(adapter: .init(transport: wire), authorizer: CouponPublisherUnavailable(), locks: locks, currentSession: { current })
        await core.load()
        XCTAssertEqual(core.rows.first?.publishedBatchCode, "BATCH-710")
        XCTAssertEqual(wire.requests.count, 1); XCTAssertFalse(core.canSubmit); XCTAssertEqual(locks.calls, 0)
        current = nil; core.synchronize()
        XCTAssertTrue(core.rows.isEmpty)
    }
    func testLateAccountEpochOrApprovalResponseCannotFillCurrentRows() async throws {
        let original = try CouponManagementSession(accountID: 1, namespace: "synthetic", epoch: 1, authorizationRevision: "scope-A")
        let changed = [try CouponManagementSession(accountID: 2, namespace: "synthetic", epoch: 1, authorizationRevision: "scope-A"),
                       try CouponManagementSession(accountID: 1, namespace: "synthetic", epoch: 2, authorizationRevision: "scope-A"),
                       try CouponManagementSession(accountID: 1, namespace: "synthetic", epoch: 1, authorizationRevision: "scope-B")]
        for replacement in changed {
            var current: CouponManagementSession? = original
            let wire = PublishedBatchReadWire(), locks = PublishedBatchNoLocks()
            wire.onSend = { current = replacement }
            let core = CouponManagementCoordinator(adapter: .init(transport: wire), authorizer: CouponPublisherUnavailable(), locks: locks, currentSession: { current })
            await core.load()
            XCTAssertTrue(core.rows.isEmpty); XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(locks.calls, 0)
        }
    }
    func testDefaultUnavailableSourceCannotProduceBatchReference() async throws {
        let owner = try CouponManagementSession(accountID: 1, namespace: "synthetic", epoch: 1, authorizationRevision: "off")
        let core = CouponManagementCoordinator(adapter: .init(), authorizer: CouponPublisherUnavailable(), locks: PublishedBatchNoLocks(), currentSession: { owner })
        await core.load()
        XCTAssertTrue(core.rows.isEmpty); XCTAssertFalse(core.canRead); XCTAssertFalse(core.canSubmit)
        XCTAssertEqual(core.issue, .unavailable)
    }
}

@MainActor private final class PublishedBatchReadWire: CouponManagementTransport {
    let isSynthetic = true
    var requests: [CouponManagementRequest] = []
    var onSend: (() -> Void)?
    func send(_ request: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        XCTAssertFalse(request.mutates); XCTAssertEqual(request.path, "/api/coupon/mypublishlist")
        return (Data(#"{"code":200,"data":[{"id":710,"code":"BATCH-710","status":1}]}"#.utf8), 200)
    }
}
@MainActor private final class PublishedBatchNoLocks: CouponManagementLocking {
    var calls = 0
    func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { calls += 1; return nil }
    func acquire(_ pending: CouponManagementPending) throws { calls += 1 }
    func release(_ pending: CouponManagementPending) throws { calls += 1 }
}
