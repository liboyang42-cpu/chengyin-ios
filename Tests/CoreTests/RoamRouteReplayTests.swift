import XCTest
@testable import QuestifyCore

@MainActor final class RoamRouteReplayTests: XCTestCase {
    private final class Reader: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = false // Local saved history does not require a network service.
        var isOfflineExample = false
        var historyReads = 0
        func history() throws -> [RoamHistoryRecord] { historyReads += 1; return [] }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
    }
    private func record(ts: Int64 = 1, points: Int = 8, duplicate: Bool = false) throws -> RoamHistoryRecord {
        let track = (0..<points).map { index in ["lat": 31.0 + (duplicate ? 0 : Double(index) * 0.0001), "lng": 121.0] }
        let raw = try JSONSerialization.data(withJSONObject: ["ts": ts, "track": track, "pois": []])
        return try JSONDecoder().decode(RoamHistoryRecord.self, from: raw)
    }
    private func identity(account: Int = 1, epoch: UInt64 = 1) throws -> RoamExperienceIdentity {
        .init(scope: try .init(market: "cn", deployment: URL(string: "https://roam-replay.example.test")!, accountID: account), epoch: epoch)
    }
    private func prepared(_ reader: Reader, _ record: RoamHistoryRecord, reduceMotion: Bool = false) -> (RoamRouteReplayState, RoamRouteReplayState.Owner) {
        let owner = RoamRouteReplayState.Owner(reader: reader, record: record)
        var state = RoamRouteReplayState(); state.update(owner: owner, active: true, reduceMotion: reduceMotion)
        return (state, owner)
    }
    func testPlanHasAtMost24MonotonicFramesAndExactFinalCount() {
        for count in [1, 2, 23, 24, 25, 1000, Int.max] {
            let plan = RoamRouteReplayPlan(segmentCount: count)
            XCTAssertLessThanOrEqual(plan.counts.count, 24)
            XCTAssertEqual(plan.counts.last, count)
            XCTAssertTrue(zip(plan.counts, plan.counts.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
            XCTAssertLessThanOrEqual(UInt64(plan.counts.count - 1) * RoamRouteReplayPlan.intervalNanoseconds, 2_760_000_000)
        }
    }
    func testZeroAndNegativePlansHaveNoFrames() {
        for count in [0, -1, Int.min] { XCTAssertTrue(RoamRouteReplayPlan(segmentCount: count).counts.isEmpty) }
    }
    func testDefaultIsFullStaticRouteWithoutAutoplayOrRead() throws {
        let reader = Reader(); let (state, owner) = prepared(reader, try record())
        XCTAssertEqual(state.phase, .ready); XCTAssertNil(state.visibleSegments); XCTAssertEqual(state.progress, 1)
        XCTAssertNotNil(state.context(for: owner)); XCTAssertEqual(reader.historyReads, 0)
    }
    func testEmptySinglePointAndIdenticalPointsCannotStart() throws {
        for (points, duplicate) in [(0, false), (1, false), (8, true)] {
            let (state, owner) = prepared(Reader(), try record(points: points, duplicate: duplicate))
            XCTAssertNil(state.context(for: owner)); XCTAssertTrue(state.plan.counts.isEmpty); XCTAssertEqual(state.progress, 0)
        }
    }
    func testReplayAdvancesToCompleteWithoutMutatingRecord() throws {
        let reader = Reader(); let value = try record(); var (state, owner) = prepared(reader, value)
        let rendered = try XCTUnwrap(state.context(for: owner)); let run = try XCTUnwrap(state.start(in: rendered, current: owner))
        XCTAssertEqual(state.visibleSegments, 0); XCTAssertEqual(state.progress, 0)
        for count in state.plan.counts { state.advance(to: count, in: run, current: owner) }
        XCTAssertEqual(state.phase, .completed); XCTAssertNil(state.visibleSegments); XCTAssertEqual(state.progress, 1)
        XCTAssertEqual(owner.record, value); XCTAssertEqual(reader.historyReads, 0)
    }
    func testRepeatedStartCannotReplaceAnActiveReplay() throws {
        var (state, owner) = prepared(Reader(), try record())
        let oldButton = try XCTUnwrap(state.context(for: owner)); let run = try XCTUnwrap(state.start(in: oldButton, current: owner))
        XCTAssertNil(state.start(in: oldButton, current: owner))
        XCTAssertNil(state.start(in: run, current: owner)); XCTAssertTrue(state.accepts(run, current: owner))
    }
    func testSkipRetiresOldFrameAndOldRenderedButton() throws {
        var (state, owner) = prepared(Reader(), try record())
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.advance(to: 2, in: run, current: owner); state.skip(in: run, current: owner)
        state.advance(to: 1, in: run, current: owner); state.skip(in: run, current: owner)
        XCTAssertEqual(state.phase, .completed); XCTAssertNil(state.visibleSegments); XCTAssertEqual(state.progress, 1)
        XCTAssertFalse(state.accepts(run, current: owner))
    }
    func testReplayAgainDoesNotAcceptPreviousFramesOrSkip() throws {
        var (state, owner) = prepared(Reader(), try record())
        let old = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.skip(in: old, current: owner)
        let fresh = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.advance(to: 7, in: old, current: owner); state.skip(in: old, current: owner)
        XCTAssertEqual(state.phase, .playing); XCTAssertEqual(state.visibleSegments, 0)
        XCTAssertTrue(state.accepts(fresh, current: owner))
    }
    func testReduceMotionStartsAtFullTerminalWithoutARequest() throws {
        var (state, owner) = prepared(Reader(), try record(), reduceMotion: true)
        let rendered = try XCTUnwrap(state.context(for: owner))
        XCTAssertNil(state.start(in: rendered, current: owner))
        XCTAssertEqual(state.phase, .completed); XCTAssertEqual(state.progress, 1)
    }
    func testEnablingReduceMotionRetiresInFlightFrame() throws {
        var (state, owner) = prepared(Reader(), try record())
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.update(owner: owner, active: true, reduceMotion: true)
        state.advance(to: 1, in: run, current: owner)
        XCTAssertEqual(state.phase, .completed); XCTAssertEqual(state.progress, 1); XCTAssertFalse(state.accepts(run, current: owner))
    }
    func testDisappearAndForegroundDoNotResumeOrResurrectOldContext() throws {
        var (state, owner) = prepared(Reader(), try record())
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.update(owner: owner, active: false, reduceMotion: false)
        XCTAssertNil(state.context(for: owner))
        state.update(owner: owner, active: true, reduceMotion: false)
        state.advance(to: 2, in: run, current: owner)
        XCTAssertEqual(state.phase, .ready); XCTAssertNil(state.visibleSegments); XCTAssertFalse(state.accepts(run, current: owner))
    }
    func testRecordABARetiresOldFrames() throws {
        let reader = Reader(); let a = try record(); let b = try record(ts: 2)
        var (state, owner) = prepared(reader, a)
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.update(owner: .init(reader: reader, record: b), active: true, reduceMotion: false)
        state.update(owner: owner, active: true, reduceMotion: false)
        XCTAssertFalse(state.accepts(run, current: owner)); XCTAssertEqual(state.phase, .ready)
    }
    func testChangedTrackWithSameTimestampRetiresOldFrames() throws {
        let reader = Reader(); var (state, owner) = prepared(reader, try record())
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        let changed = RoamRouteReplayState.Owner(reader: reader, record: try record(points: 4))
        state.update(owner: changed, active: true, reduceMotion: false)
        XCTAssertEqual(state.totalSegments, 3); XCTAssertFalse(state.accepts(run, current: changed))
    }
    func testReaderReplacementWithSameSessionRejectsOldCallbacks() throws {
        let first = Reader(); let second = Reader(); first.identity = try identity(); second.identity = first.identity
        let value = try record(); var (state, owner) = prepared(first, value)
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        let replaced = RoamRouteReplayState.Owner(reader: second, record: value)
        XCTAssertFalse(state.accepts(run, current: replaced))
        state.update(owner: replaced, active: true, reduceMotion: false); XCTAssertFalse(state.accepts(run, current: replaced))
    }
    func testLiveIdentityEpochConfigurationAndLogoutChangesRejectOldCallbacks() throws {
        let reader = Reader(); reader.identity = try identity(); let value = try record()
        var (state, owner) = prepared(reader, value)
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        reader.identity = try identity(epoch: 2)
        XCTAssertFalse(state.accepts(run, current: .init(reader: reader, record: value)))
        reader.identity = try identity(account: 2)
        XCTAssertFalse(state.accepts(run, current: .init(reader: reader, record: value)))
        reader.identity = nil
        XCTAssertFalse(state.accepts(run, current: .init(reader: reader, record: value)))
        reader.identity = owner.identity; reader.isConfigured = true
        XCTAssertFalse(state.accepts(run, current: .init(reader: reader, record: value)))
    }
    func testNegativeOutOfOrderAndLargeCountsStayBounded() throws {
        var (state, owner) = prepared(Reader(), try record())
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        state.advance(to: -10, in: run, current: owner); XCTAssertEqual(state.visibleSegments, 0)
        state.advance(to: 3, in: run, current: owner); state.advance(to: 1, in: run, current: owner)
        XCTAssertEqual(state.visibleSegments, 3)
        state.advance(to: Int.max, in: run, current: owner)
        XCTAssertEqual(state.phase, .completed); XCTAssertEqual(state.progress, 1)
    }
    func testCanonicallyEquivalentNamespaceBytesStillRetireReplayAuthority() throws {
        let reader = Reader(); let value = try record()
        let endpoint = URL(string: "https://roam-replay.example.test")!
        reader.identity = .init(scope: try .init(market: "cn", deployment: endpoint, accountID: 1, namespace: "e\u{301}"), epoch: 1)
        var (state, owner) = prepared(reader, value)
        let run = try XCTUnwrap(state.start(in: XCTUnwrap(state.context(for: owner)), current: owner))
        reader.identity = .init(scope: try .init(market: "cn", deployment: endpoint, accountID: 1, namespace: "\u{e9}"), epoch: 1)
        let changed = RoamRouteReplayState.Owner(reader: reader, record: value)
        XCTAssertEqual(owner.identity, changed.identity) // Swift String equality normalizes.
        XCTAssertNotEqual(owner.storageKey, changed.storageKey)
        XCTAssertFalse(state.accepts(run, current: changed))
    }

}
