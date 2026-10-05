import XCTest
@testable import QuestifyCore

final class PlayObjectCardReceiptTests: XCTestCase {
    private let card = #"{"id":901,"title":"Synthetic cup","sourceUrl":"https://example.com/cup.png","frames":["https://example.com/a.png","https://example.com/b.png"],"cardStyle":"foil"}"#
    private func owner(_ epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try .init(accountID: 9001, epoch: epoch, namespace: "synthetic", token: "synthetic")
    }
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    private func state(version: Int = 2, node: Int = 701, mode: String = "CARD", passed: Bool = true,
                       status: String = "RUNNING", receipt: String? = nil) throws -> PlayAdvancedState {
        let extra = receipt.map { ",\"objectCard\":" + $0 } ?? ""
        return try PlayAdvancedState(wire("{\"sessionId\":501,\"activityId\":41,\"topicId\":71,\"nodeId\":\(node),\"version\":\(version),\"status\":\"\(status)\",\"playKit\":{\"photoCheck\":{\"mode\":\"\(mode)\",\"passed\":\(passed)}}\(extra)}"))
    }
    private var pending: PlayAdvancedPending { .init(sessionID: 501, version: 1, key: "synthetic-request", action: "SUBMIT_PHOTO_CHECK", payload: [:]) }
    func testDecodesTopLevelReceiptWithoutChangingGameOutcome() throws {
        let value = try state(receipt: card)
        XCTAssertEqual(value.objectCard?.id, "901")
        XCTAssertEqual(value.objectCard?.frames.count, 2)
        XCTAssertEqual(value.playKit["photoCheck"]["passed"].bool, true)
    }
    func testMalformedCardDoesNotRejectCommittedResult() throws {
        let value = try state(receipt: #"{"id":0,"title":""}"#)
        XCTAssertNil(value.objectCard)
        XCTAssertEqual(value.playKit["photoCheck"]["passed"].bool, true)
    }
    func testBoundedDecoderRejectsInvalidIdentityAndFrames() throws {
        for raw in [#"{"id":"../bad","title":"x"}"#, #"{"id":1,"title":"x","frames":[7]}"#, #"{"id":1,"title":"x","caption":false}"#] {
            XCTAssertNil(PlayObjectCardReceiptDecoder.decode(try wire(raw)))
        }
        let frames = String(repeating: "\"x\",", count: 72) + "\"x\""
        XCTAssertNil(PlayObjectCardReceiptDecoder.decode(try wire("{\"id\":1,\"title\":\"x\",\"frames\":[\(frames)]}")))
    }
    func testPassedAloneDoesNotCreateCard() throws {
        var cache = PlayObjectCardReceiptCache()
        cache.accept(try state(), owner: try owner(), pending: pending, requestedCard: true)
        XCTAssertNil(cache.receipt)
    }
    func testOnlyMatchingCardSubmissionCanReveal() throws {
        for requested in [false, true] {
            var cache = PlayObjectCardReceiptCache()
            cache.accept(try state(mode: "", receipt: card), owner: try owner(), pending: pending, requestedCard: requested)
            XCTAssertNil(cache.receipt)
        }
        var cache = PlayObjectCardReceiptCache()
        cache.accept(try state(receipt: card), owner: try owner(), pending: pending, requestedCard: false)
        XCTAssertNil(cache.receipt)
    }
    func testMissingFieldRefreshPreservesReceiptAndVersion() throws {
        var cache = PlayObjectCardReceiptCache()
        cache.accept(try state(receipt: card), owner: try owner(), pending: pending, requestedCard: true)
        let accepted = try XCTUnwrap(cache.receipt)
        cache.reconcile(try state(version: 3), owner: try owner())
        XCTAssertEqual(cache.receipt, accepted)
        cache.accept(try state(receipt: card.replacingOccurrences(of: "901", with: "902")), owner: try owner(), pending: pending, requestedCard: true)
        XCTAssertEqual(cache.receipt?.card.id, "901")
    }
    func testOwnerNodeModeAndRevocationClearRetainedReceipt() throws {
        for replacement in [try state(node: 702), try state(mode: ""), try state(passed: false), try state(status: "CANCELLED"), try state(version: 1)] {
            var cache = PlayObjectCardReceiptCache()
            cache.accept(try state(receipt: card), owner: try owner(), pending: pending, requestedCard: true)
            cache.reconcile(replacement, owner: try owner())
            XCTAssertNil(cache.receipt)
        }
        var cache = PlayObjectCardReceiptCache()
        cache.accept(try state(receipt: card), owner: try owner(), pending: pending, requestedCard: true)
        cache.reconcile(try state(), owner: try owner(2))
        XCTAssertNil(cache.receipt)
    }
    func testRefreshAloneCannotAdoptCard() throws {
        var cache = PlayObjectCardReceiptCache()
        cache.reconcile(try state(receipt: card), owner: try owner())
        XCTAssertNil(cache.receipt)
    }
    func testVersionMustAdvanceAndSessionMustMatch() throws {
        var cache = PlayObjectCardReceiptCache()
        cache.accept(try state(version: 1, receipt: card), owner: try owner(), pending: pending, requestedCard: true)
        XCTAssertNil(cache.receipt)
        let mismatch = PlayAdvancedPending(sessionID: 999, version: 1, key: "synthetic", action: "SUBMIT_PHOTO_CHECK", payload: [:])
        cache.accept(try state(receipt: card), owner: try owner(), pending: mismatch, requestedCard: true)
        XCTAssertNil(cache.receipt)
    }
}
