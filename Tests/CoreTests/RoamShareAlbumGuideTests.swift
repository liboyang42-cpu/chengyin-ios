import XCTest
@testable import QuestifyCore

final class RoamShareAlbumGuideTests: XCTestCase {
    private func selection(_ fields: [String: Any] = [:], route: Bool = false) throws -> RoamSharePhotoSaveState.Selection {
        let fields = ["ts": 1700000000000 as Any].merging(fields) { _, new in new }
        let record = try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject: fields))
        return .init(record: record, includeRoute: route)
    }
    func testMissingStatisticsAreNotInventedAsZero() throws {
        let copy = RoamShareAlbumGuideState.Copy(record: try selection().record)
        XCTAssertNil(copy.shops); XCTAssertNil(copy.kilometers); XCTAssertNil(copy.explorationPercent)
    }
    func testMeasuredZeroIsRetained() throws {
        let copy = RoamShareAlbumGuideState.Copy(record: try selection(["shops": 0, "distance": 0, "explorePct": 0]).record)
        XCTAssertEqual(copy.shops, 0); XCTAssertEqual(copy.kilometers, 0); XCTAssertEqual(copy.explorationPercent, 0)
    }
    func testOnlyValidExplorationPercentIsCopied() throws {
        for value in [-1, 101, Int.max] { XCTAssertNil(RoamShareAlbumGuideState.Copy(record: try selection(["explorePct": value]).record).explorationPercent) }
        XCTAssertEqual(RoamShareAlbumGuideState.Copy(record: try selection(["explorePct": 100]).record).explorationPercent, 100)
    }
    func testUnknownDateIsNotToday() throws {
        XCTAssertNil(RoamShareAlbumGuideState.Copy(record: try selection(["ts": 0]).record).recordedAt)
    }
    func testCopyHasNoLocationMediaOrIdentityFields() throws {
        let copy = RoamShareAlbumGuideState.Copy(record: try selection(["zone": "SECRET", "photos": ["https://example.com/private.jpg"], "serverSessionID": 91, "track": [["lat": 1, "lng": 2]]]).record)
        XCTAssertEqual(Set(Mirror(reflecting: copy).children.compactMap(\.label)), ["recordedAt", "shops", "kilometers", "explorationPercent"])
    }
    func testDestinationSelectionAndPermissionOrSavingAreNotSuccess() throws {
        var state = RoamShareAlbumGuideState(); let selection = try selection()
        let request = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
        let phases: [RoamSharePhotoSaveState.Phase] = [.ready, .requestingPermission, .saving]
        for phase in phases {
            state.receive(request, phase: phase, current: selection, sourceIsCurrent: true)
            XCTAssertNil(state.guide); XCTAssertTrue(state.accepts(request))
        }
    }
    func testOnlySavedReceiptProducesChosenGuide() throws {
        for destination in RoamShareAlbumGuideState.Destination.allCases {
            var state = RoamShareAlbumGuideState(); let selection = try selection(["shops": 3])
            let request = try XCTUnwrap(state.begin(destination: destination, selection: selection, saveInFlight: false))
            state.receive(request, phase: .saved, current: selection, sourceIsCurrent: true)
            XCTAssertEqual(state.guide?.destination, destination); XCTAssertEqual(state.guide?.copy.shops, 3); XCTAssertNil(state.pending)
        }
    }
    func testAllFailedSaveStatesProduceNoGuideAndAllowExplicitRetry() throws {
        let phases: [RoamSharePhotoSaveState.Phase] = [.permissionDenied, .restricted, .unavailable, .sourceChanged, .failed]
        for phase in phases {
            var state = RoamShareAlbumGuideState(); let selection = try selection()
            let request = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
            state.receive(request, phase: phase, current: selection, sourceIsCurrent: true)
            XCTAssertNil(state.guide); XCTAssertNil(state.pending)
            XCTAssertNotNil(state.begin(destination: .xiaohongshu, selection: selection, saveInFlight: false))
        }
    }
    func testRepeatedDestinationTapCannotReplaceInFlightRequest() throws {
        var state = RoamShareAlbumGuideState(); let selection = try selection()
        let request = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
        XCTAssertNil(state.begin(destination: .xiaohongshu, selection: selection, saveInFlight: false))
        XCTAssertTrue(state.accepts(request))
    }
    func testUnrelatedPhotoSaveInFlightBlocksGuideRequest() throws {
        var state = RoamShareAlbumGuideState()
        XCTAssertNil(state.begin(destination: .moments, selection: try selection(), saveInFlight: true)); XCTAssertNil(state.pending)
    }
    func testChangedRecordOrRouteCannotReceiveOldSave() throws {
        let original = try selection()
        for newer in [try selection(["shops": 2]), try selection(route: true)] {
            var state = RoamShareAlbumGuideState()
            let request = try XCTUnwrap(state.begin(destination: .moments, selection: original, saveInFlight: false))
            state.receive(request, phase: .saved, current: newer, sourceIsCurrent: true)
            XCTAssertNil(state.guide); XCTAssertNil(state.pending)
        }
    }
    func testOwnerRevocationPreventsGuideEvenAfterConfirmedSave() throws {
        var state = RoamShareAlbumGuideState(); let selection = try selection()
        let request = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
        state.receive(request, phase: .saved, current: selection, sourceIsCurrent: false)
        XCTAssertNil(state.guide); XCTAssertNil(state.pending)
    }
    func testDismissalAndReopeningRetireLateReceipt() throws {
        var state = RoamShareAlbumGuideState(); let selection = try selection()
        let old = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
        state.invalidate()
        let next = try XCTUnwrap(state.begin(destination: .xiaohongshu, selection: selection, saveInFlight: false))
        state.receive(old, phase: .saved, current: selection, sourceIsCurrent: true)
        XCTAssertNil(state.guide); XCTAssertTrue(state.accepts(next))
        state.receive(next, phase: .saved, current: selection, sourceIsCurrent: true)
        XCTAssertEqual(state.guide?.destination, .xiaohongshu)
    }
    func testGuideMustCloseBeforeAnotherDestinationCanOpen() throws {
        var state = RoamShareAlbumGuideState(); let selection = try selection()
        let request = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
        state.receive(request, phase: .saved, current: selection, sourceIsCurrent: true)
        XCTAssertNil(state.begin(destination: .xiaohongshu, selection: selection, saveInFlight: false))
        state.dismissGuide(); XCTAssertNotNil(state.begin(destination: .xiaohongshu, selection: selection, saveInFlight: false))
    }
    func testDuplicateSuccessCannotReplaceDisplayedGuide() throws {
        var state = RoamShareAlbumGuideState(); let selection = try selection()
        let request = try XCTUnwrap(state.begin(destination: .moments, selection: selection, saveInFlight: false))
        state.receive(request, phase: .saved, current: selection, sourceIsCurrent: true)
        let id = state.guide?.id
        state.receive(request, phase: .saved, current: selection, sourceIsCurrent: true)
        XCTAssertEqual(state.guide?.id, id)
    }
}
