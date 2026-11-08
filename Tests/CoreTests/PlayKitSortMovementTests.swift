import XCTest
@testable import QuestifyCore

final class PlayKitSortMovementTests: XCTestCase {
    func testRetainedRowActionMovesItsOriginalIDAfterAnotherRowReorders() throws {
        // The visible B action originally had index 1. Another row moves before
        // that retained action runs; index 1 now belongs to A, not B.
        let afterOtherMove = try XCTUnwrap(PlayKitSortMovement.moving("b", by: -1, in: ["a", "b", "c"]))
        XCTAssertEqual(afterOtherMove, ["b", "a", "c"])
        let result = try XCTUnwrap(PlayKitSortMovement.moving("b", by: 1, in: afterOtherMove))
        XCTAssertEqual(result, ["a", "b", "c"])
        XCTAssertEqual(afterOtherMove[1], "a")
    }

    func testBoundaryActionCannotMoveADifferentItemAfterItsTargetMovesToAnEdge() throws {
        let order = try XCTUnwrap(PlayKitSortMovement.moving("b", by: -1, in: ["a", "b", "c"]))
        XCTAssertNil(PlayKitSortMovement.moving("b", by: -1, in: order))
        XCTAssertEqual(order, ["b", "a", "c"])
        XCTAssertNil(PlayKitSortMovement.moving("c", by: 1, in: order))
    }

    func testRemovedUnknownAmbiguousAndInvalidMovementAreRefused() {
        XCTAssertNil(PlayKitSortMovement.moving("b", by: 1, in: ["a", "c"]))
        XCTAssertNil(PlayKitSortMovement.moving("missing", by: -1, in: ["a", "b"]))
        XCTAssertNil(PlayKitSortMovement.moving("a", by: 1, in: ["a", "a", "b"]))
        XCTAssertNil(PlayKitSortMovement.moving("a", by: 0, in: ["a", "b"]))
        XCTAssertNil(PlayKitSortMovement.moving("a", by: 2, in: ["a", "b", "c"]))
        XCTAssertNil(PlayKitSortMovement.moving("a", by: 1, in: []))
    }

    func testMovedIDsStillUseTheOriginalSortPayloadAndServerResultBoundary() throws {
        let segment: PlayWireValue = .object([
            "items": .array([
                .object(["id": .string("a"), "label": .string("First")]),
                .object(["id": .string("b"), "label": .string("Second")])]),
            "finished": .bool(false)
        ])
        let order = try XCTUnwrap(PlayKitSortMovement.moving("b", by: -1, in: ["a", "b"]))
        let payload: [String: PlayWireValue] = ["order": .array(order.map(PlayWireValue.string))]
        try PlayKitInputContract.validate(kind: "sort", action: "SUBMIT_SORT", payload: payload, segment: segment)
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "sort", action: "SUBMIT_SORT", detail: payload), payload)
        XCTAssertEqual(payload, ["order": .array([.string("b"), .string("a")])])
        let projection = PlayKitScreenProjection(kind: .sort, segment: segment)
        XCTAssertFalse(projection.complete)
        XCTAssertNil(projection.reportedPass)
        XCTAssertNil(projection.reasoningResultKey)
        var finished = segment.object!
        finished["finished"] = .bool(true)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "sort", action: "SUBMIT_SORT", payload: payload, segment: .object(finished)))
    }
}
