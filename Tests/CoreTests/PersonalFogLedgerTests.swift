import XCTest
@testable import QuestifyCore

final class PersonalFogLedgerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 4_000_000)
    private func cell(_ code: String) throws -> FogCell { try FogCell(grid: .legacyRoamTile, code: code) }
    private func fix(accuracy: Double = 10, age: TimeInterval = 0) throws -> RoamDeviceFix {
        try .init(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.4)!, accuracyMeters: accuracy, measuredAt: now.addingTimeInterval(-age), datum: .wgs84)
    }
    private var policy: PersonalFogSamplePolicy { try! .init(maxAccuracyMeters: 50, maxAge: 30, maxBatch: 2) }

    func testRevealSyncStaysDisabled() throws {
        XCTAssertFalse(PersonalFogFeature.revealSyncEnabled)
        var ledger = try PersonalFogLedger(ownerScope: "acct-1")
        XCTAssertThrowsError(try ledger.nextBatch(policy: policy)) { XCTAssertEqual($0 as? PersonalFogFailure, .featureDisabled) }
    }
    func testInvalidCellsAndPoliciesRejected() {
        XCTAssertThrowsError(try cell("")); XCTAssertThrowsError(try cell("ail")); XCTAssertThrowsError(try cell("wtw3sjq6qx2kq"))
        XCTAssertThrowsError(try FogCell(grid: FogGridVersion(id: "h3-r9"), code: "wtw3sj"))
        XCTAssertThrowsError(try PersonalFogSamplePolicy(maxAccuracyMeters: 0, maxAge: 30, maxBatch: 1))
        XCTAssertThrowsError(try PersonalFogSamplePolicy(maxAccuracyMeters: 10, maxAge: 30, maxBatch: 0))
    }
    func testServerPagesUnionMergeForwardOnlyAndOwnerScoped() throws {
        var ledger = try PersonalFogLedger(ownerScope: "acct-1")
        try ledger.applyServerPage(owner: "acct-1", cells: ["wtw3sj", "wtw3sk"], nextCursor: 5)
        try ledger.applyServerPage(owner: "acct-1", cells: ["wtw3sk", "wtw3sm"], nextCursor: 9)
        XCTAssertEqual(ledger.confirmed.count, 3)
        XCTAssertThrowsError(try ledger.applyServerPage(owner: "acct-1", cells: [], nextCursor: 4)) { XCTAssertEqual($0 as? PersonalFogFailure, .cursorRegression) }
        XCTAssertThrowsError(try ledger.applyServerPage(owner: "acct-2", cells: ["wtw3sn"], nextCursor: 10)) { XCTAssertEqual($0 as? PersonalFogFailure, .ownerMismatch) }
        XCTAssertEqual(ledger.confirmed.count, 3)
        XCTAssertThrowsError(try ledger.applyServerPage(owner: "acct-1", cells: ["bad!"], nextCursor: 10))
        XCTAssertEqual(ledger.readCursor, 9)
    }
    func testOnlyQualifiedSamplesPredict() throws {
        var ledger = try PersonalFogLedger(ownerScope: "acct-1")
        XCTAssertThrowsError(try ledger.predict(cell("wtw3sj"), fix: fix(accuracy: 80), policy: policy, now: now))
        XCTAssertThrowsError(try ledger.predict(cell("wtw3sj"), fix: fix(age: 60), policy: policy, now: now))
        XCTAssertThrowsError(try ledger.predict(cell("wtw3sj"), fix: fix(age: -30), policy: policy, now: now))
        try ledger.predict(cell("wtw3sj"), fix: fix(), policy: policy, now: now)
        XCTAssertEqual(ledger.state(of: try cell("wtw3sj")), .pendingSync)
        XCTAssertEqual(ledger.state(of: try cell("wtw3sk")), .hidden)
    }
    func testBatchRetryKeepsKeyAndRejectionRollsBack() throws {
        var ledger = try PersonalFogLedger(ownerScope: "acct-1")
        for code in ["wtw3sj", "wtw3sk", "wtw3sm"] { try ledger.predict(cell(code), fix: fix(), policy: policy, now: now) }
        let key = UUID()
        let batch = try XCTUnwrap(ledger.nextBatchForContract(policy: policy, key: key))
        XCTAssertEqual(batch.cells.count, 2)
        XCTAssertEqual(ledger.nextBatchForContract(policy: policy, key: UUID()), batch)
        ledger.acknowledge(UUID(), accepted: Set(batch.cells), rejected: [])
        XCTAssertNotNil(ledger.inFlight)
        ledger.acknowledge(key, accepted: [batch.cells[0]], rejected: [batch.cells[1]])
        XCTAssertEqual(ledger.state(of: batch.cells[0]), .confirmed)
        XCTAssertEqual(ledger.state(of: batch.cells[1]), .hidden)
        XCTAssertEqual(ledger.lastRejected, [batch.cells[1]])
        XCTAssertEqual(ledger.pendingCount, 1)
        XCTAssertNil(ledger.inFlight)
    }
    func testServerConfirmationClearsMatchingPrediction() throws {
        var ledger = try PersonalFogLedger(ownerScope: "acct-1")
        try ledger.predict(cell("wtw3sj"), fix: fix(), policy: policy, now: now)
        try ledger.applyServerPage(owner: "acct-1", cells: ["wtw3sj"], nextCursor: 1)
        XCTAssertEqual(ledger.state(of: try cell("wtw3sj")), .confirmed)
        XCTAssertEqual(ledger.pendingCount, 0)
        try ledger.predict(cell("wtw3sj"), fix: fix(), policy: policy, now: now)
        XCTAssertEqual(ledger.pendingCount, 0)
    }
}
