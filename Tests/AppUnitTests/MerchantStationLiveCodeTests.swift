import XCTest
@testable import Questify

@MainActor private final class StationLiveCodeReader: MerchantContentServing {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var permitsWrites = false
    var loadCount = 0
    var writeCount = 0
    var observedAt = Date(timeIntervalSince1970: 1_800_000_001)
    var returnedQuery: MerchantContentQuery?
    var returnedScope: UUID?
    var merchantID = 7
    var active = true
    var value: MerchantContentValue = .object([
        "nodeId": .integer(62), "nodeName": .string("Synthetic station"), "ttlMs": .integer(60_000),
        "code": .string("v1.62.play_checkin.1800000060000.-9223372036854775808." + String(repeating: "A", count: 43)),
        "qrcodeUrl": .string("https://invalid.example/never-fetched")])
    func load(_ query: MerchantContentQuery) async throws -> MerchantContentSnapshot {
        loadCount += 1
        let access = try JSONDecoder().decode(MerchantAccess.self, from: Data("{\"active\":\(active),\"merchant\":{\"id\":\(merchantID)},\"roleCode\":\"MERCHANT_CHECKIN\",\"permissions\":[]}".utf8))
        return .init(query: returnedQuery ?? query, scope: returnedScope ?? scope, access: access, value: value, observedAt: observedAt)
    }
    func perform(_ command: MerchantContentCommand, baseline: MerchantContentSnapshot) async throws -> MerchantContentReceipt { writeCount += 1; throw MerchantContentFailure.disabled }
    func pending() throws -> [MerchantContentPendingRecord] { [] }
    func reconcile(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { writeCount += 1; throw MerchantContentFailure.disabled }
    func retryStation(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { writeCount += 1; throw MerchantContentFailure.disabled }
}

@MainActor final class MerchantStationLiveCodeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_002)
    private let uptime: TimeInterval = 100
    private func harness(_ suppliedReader: StationLiveCodeReader? = nil) async -> (MerchantContentViewModel, StationLiveCodeReader) {
        let reader = suppliedReader ?? StationLiveCodeReader()
        let owner = MerchantContentViewModel(service: reader, query: .liveCode(activityID: 80, nodeID: 62))
        await owner.load(); return (owner, reader)
    }
    private func receipt(_ snapshot: MerchantContentSnapshot) -> MerchantStationLiveCodeReceipt? {
        .init(snapshot: snapshot, now: now, uptime: uptime)
    }
    private func lease(_ owner: MerchantContentViewModel) throws -> MerchantStationLiveCodeLease {
        .init(owner: owner, snapshot: try XCTUnwrap(owner.coordinator.snapshot), now: now, uptime: uptime)
    }
    private func display(_ lease: MerchantStationLiveCodeLease) -> MerchantStationLiveCodeReceipt? { lease.display(now: now, uptime: uptime) }
    private func changing(_ snapshot: MerchantContentSnapshot, _ key: String, _ value: MerchantContentValue) -> MerchantContentSnapshot {
        var fields = snapshot.value.object!; fields[key] = value
        return .init(query: snapshot.query, scope: snapshot.scope, access: snapshot.access, value: .object(fields), observedAt: snapshot.observedAt)
    }
    func testExactReceivedCodeAndNodeNameArePreservedWithoutFetchingImageURL() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner); let value = try XCTUnwrap(display(state))
        XCTAssertEqual(value.code, reader.value["code"].text); XCTAssertEqual(value.nodeName, "Synthetic station")
        XCTAssertEqual(value.remainingSeconds(now: now, uptime: uptime), 58)
        XCTAssertEqual(reader.loadCount, 1); XCTAssertEqual(reader.writeCount, 0); XCTAssertFalse(reader.permitsWrites)
    }
    func testWrongNodeAndNonIntegerNodeFailClosed() async throws {
        let (owner, _) = await harness(); let snapshot = try XCTUnwrap(owner.coordinator.snapshot)
        for node in [MerchantContentValue.integer(63), .string("62"), .decimal(62.5), .null] { XCTAssertNil(receipt(changing(snapshot, "nodeId", node))) }
    }
    func testOtherPurposeVersionOrTokenNodeCannotDisplay() async throws {
        let (owner, _) = await harness(); let s = try XCTUnwrap(owner.coordinator.snapshot); let code = s.value["code"].text!
        for invalid in [code.replacingOccurrences(of: "play_checkin", with: "ticket"), code.replacingOccurrences(of: "v1.", with: "v2."), code.replacingOccurrences(of: ".62.", with: ".63."), code.replacingOccurrences(of: ".62.", with: ".062.")] {
            XCTAssertNil(receipt(changing(s, "code", .string(invalid))))
        }
    }
    func testMalformedUnboundedAndWhitespaceTokensFailClosed() async throws {
        let (owner, _) = await harness(); let s = try XCTUnwrap(owner.coordinator.snapshot); let code = s.value["code"].text!
        for invalid in ["", " " + code, code + "\n", code + ".extra", String(code.dropLast()), String(repeating: "A", count: 2_049), code.replacingOccurrences(of: "play_checkin", with: "play_验"), code.replacingOccurrences(of: "-9223372036854775808", with: "9223372036854775808")] {
            XCTAssertNil(receipt(changing(s, "code", .string(invalid))))
        }
    }
    func testInvalidRelativeTTLDoesNotCreateDisplayLifetime() async throws {
        let (owner, _) = await harness(); let s = try XCTUnwrap(owner.coordinator.snapshot)
        for ttl in [MerchantContentValue.integer(0), .integer(-1), .integer(60_001), .string("60000"), .null] { XCTAssertNil(receipt(changing(s, "ttlMs", ttl))) }
    }
    func testExpiredEqualityAndOverlongAbsoluteExpiryAreRejectedAtConstruction() async throws {
        let (owner, _) = await harness(); let s = try XCTUnwrap(owner.coordinator.snapshot); let code = s.value["code"].text!
        for expiry in ["1800000001000", "1800000002000", "1800000062000", "9007199254740992", "01800000060000", "1e12"] {
            XCTAssertNil(receipt(changing(s, "code", .string(code.replacingOccurrences(of: "1800000060000", with: expiry)))))
        }
    }
    func testAbsoluteExpiryWinsOverFreshObservationAndTTL() async throws {
        let (owner, _) = await harness(); let s = try XCTUnwrap(owner.coordinator.snapshot)
        let late = MerchantContentSnapshot(query: s.query, scope: s.scope, access: s.access, value: s.value, observedAt: now.addingTimeInterval(100))
        XCTAssertNil(MerchantStationLiveCodeReceipt(snapshot: late, now: now.addingTimeInterval(100), uptime: uptime))
    }
    func testCountdownCannotSurviveExpiryOrClockRollback() async throws {
        let (owner, _) = await harness(); let value = try XCTUnwrap(receipt(try XCTUnwrap(owner.coordinator.snapshot)))
        XCTAssertEqual(value.remainingSeconds(now: now.addingTimeInterval(58), uptime: uptime + 58), 0)
        XCTAssertEqual(value.remainingSeconds(now: now.addingTimeInterval(1), uptime: uptime + 59), 0)
        XCTAssertEqual(value.remainingSeconds(now: now.addingTimeInterval(-1), uptime: uptime + 1), 0)
        XCTAssertEqual(value.remainingSeconds(now: now, uptime: uptime - 1), 0)
        XCTAssertEqual(value.remainingSeconds(now: now, uptime: .nan), 0)
    }
    func testWrongQueryAndFutureObservationCannotDisplay() async throws {
        let (owner, _) = await harness(); let s = try XCTUnwrap(owner.coordinator.snapshot)
        XCTAssertNil(receipt(.init(query: .poster(nodeID: 62), scope: s.scope, access: s.access, value: s.value, observedAt: s.observedAt)))
        XCTAssertNil(receipt(.init(query: s.query, scope: s.scope, access: s.access, value: s.value, observedAt: now.addingTimeInterval(1))))
    }
    func testScopeChangeImmediatelyHidesReceiptBeforeRetirementCallback() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner); reader.scope = UUID()
        XCTAssertNil(display(state)); XCTAssertEqual(reader.loadCount, 1); XCTAssertEqual(reader.writeCount, 0)
    }
    func testSignOutRetirementCannotBeUndoneBySignIn() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner); reader.isAuthenticated = false
        XCTAssertNil(display(state)); state.tick(now: now, uptime: uptime); reader.isAuthenticated = true
        XCTAssertNil(display(state)); XCTAssertTrue(state.retired)
    }
    func testConfigurationLossImmediatelyHidesReceipt() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner); reader.isConfigured = false
        XCTAssertNil(display(state))
    }
    func testRevisionChangeImmediatelyHidesWithoutManualRetirement() async throws {
        let (owner, _) = await harness(); let state = try lease(owner); owner.revision += 1
        XCTAssertNil(display(state))
    }
    func testSameDataRefreshWithChangedObservedAtInvalidatesWithoutViewRevisionChange() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner); let originalRevision = owner.revision
        reader.observedAt = now; await owner.coordinator.load()
        XCTAssertEqual(owner.revision, originalRevision); XCTAssertNil(display(state))
    }
    func testStoreChangeInvalidatesWithoutViewRevisionChange() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner); reader.merchantID = 8; await owner.coordinator.load()
        XCTAssertNil(display(state))
    }
    func testMismatchedReceiptScopeAndQueryAreRejected() async throws {
        let reader = StationLiveCodeReader(); reader.returnedScope = UUID()
        let (owner, _) = await harness(reader); XCTAssertNil(display(try lease(owner)))
        reader.returnedScope = nil; reader.returnedQuery = .poster(nodeID: 62); await owner.load()
        XCTAssertNil(display(try lease(owner)))
    }
    func testInactiveAccessCannotDisplayEvenIfReaderReturnsReceipt() async throws {
        let reader = StationLiveCodeReader(); reader.active = false
        let (owner, _) = await harness(reader); XCTAssertNil(display(try lease(owner)))
    }
    func testSceneOrDepartureRetirementClearsOnlyOwnedSnapshotAndNeverRequests() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner)
        state.retire(clearOwnedSnapshot: true); XCTAssertNil(display(state)); XCTAssertNil(owner.coordinator.snapshot)
        state.retire(clearOwnedSnapshot: true); XCTAssertEqual(reader.loadCount, 1); XCTAssertEqual(reader.writeCount, 0)
    }
    func testRetiringOldLeaseCannotClearNewReceipt() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner)
        reader.observedAt = now; await owner.load(); let fresh = owner.coordinator.snapshot
        state.retire(clearOwnedSnapshot: true)
        XCTAssertEqual(owner.coordinator.snapshot, fresh); XCTAssertEqual(owner.coordinator.snapshot?.observedAt, now)
        XCTAssertNil(display(state)); XCTAssertEqual(reader.loadCount, 2)
    }
    func testExpiredLeaseStillClearsOriginalSnapshotOnLaterDeparture() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner)
        state.tick(now: now.addingTimeInterval(58), uptime: uptime + 58)
        XCTAssertNil(display(state)); XCTAssertNotNil(owner.coordinator.snapshot)
        state.retire(clearOwnedSnapshot: true)
        XCTAssertNil(owner.coordinator.snapshot); XCTAssertEqual(reader.loadCount, 1); XCTAssertEqual(reader.writeCount, 0)
    }
    func testInvalidInitialReceiptStillClearsOriginalSnapshotOnDeparture() async throws {
        let reader = StationLiveCodeReader(); var fields = reader.value.object!; fields["code"] = .string("invalid"); reader.value = .object(fields)
        let (owner, _) = await harness(reader); let state = try lease(owner)
        XCTAssertTrue(state.retired); XCTAssertNil(display(state)); XCTAssertNotNil(owner.coordinator.snapshot)
        state.retire(clearOwnedSnapshot: true)
        XCTAssertNil(owner.coordinator.snapshot); XCTAssertEqual(reader.loadCount, 1); XCTAssertEqual(reader.writeCount, 0)
    }
    func testExpiredOldLeaseCannotClearNewReceiptEvenWithSameObservationTime() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner)
        state.tick(now: now.addingTimeInterval(58), uptime: uptime + 58)
        var fields = reader.value.object!; fields["code"] = .string(fields["code"]!.text!.replacingOccurrences(of: "1800000060000", with: "1800000060001"))
        reader.value = .object(fields); await owner.load(); let fresh = try XCTUnwrap(owner.coordinator.snapshot)
        state.retire(clearOwnedSnapshot: true)
        XCTAssertEqual(owner.coordinator.snapshot, fresh); XCTAssertEqual(owner.coordinator.snapshot?.observedAt, fresh.observedAt)
        XCTAssertEqual(reader.loadCount, 2); XCTAssertEqual(reader.writeCount, 0)
    }
    func testExpiryTickIsPermanentAndDoesNotIssueReplacement() async throws {
        let (owner, reader) = await harness(); let state = try lease(owner)
        state.tick(now: now.addingTimeInterval(58), uptime: uptime + 58)
        XCTAssertNil(display(state)); XCTAssertTrue(state.retired); XCTAssertEqual(reader.loadCount, 1)
    }
}
