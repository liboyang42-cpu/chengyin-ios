import XCTest
@testable import QuestifyCore

@MainActor final class OwnerDraftBrowserTests: XCTestCase {
    private func context(account: Int = 7, role: String = "player", realm: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://draft-browser.example")!, role: role,
              session: try .init(accountID: account, epoch: 1, namespace: realm, token: "synthetic"))
    }
    private func record(id: Int64 = 11, owner: Int64 = 7, type: String = "ACTIVITY", version: Int64 = 2,
                        key: String = "synthetic", time: Any? = "2026-10-03T08:00:00+08:00") throws -> ContentDraftRecord {
        var object: [String: Any] = ["id": id, "ownerMemberId": owner, "businessType": type, "clientDraftKey": key,
            "payloadJson": "{}", "payloadHash": ContentDraftRecord.hash("{}"), "status": "DRAFT",
            "version": version, "updatedByDevice": "synthetic"]
        if let time { object["updateTime"] = time }
        return try JSONDecoder().decode(ContentDraftRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private final class Reader: ContentDraftReading {
        var records: [ContentDraftRecord] = []
        var restored: ContentDraftRecord?
        var listCalls = 0, restoreCalls = 0
        var failure: ContentDraftIssue?
        var duringList: (() -> Void)?
        var duringRestore: (() -> Void)?
        var pauseList = false, pauseRestore = false
        var listWait: CheckedContinuation<[ContentDraftRecord], Error>?
        var restoreWait: CheckedContinuation<ContentDraftRecord, Error>?
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] {
            listCalls += 1; XCTAssertNil(type); duringList?()
            if let failure { throw failure }
            if pauseList { return try await withCheckedThrowingContinuation { listWait = $0 } }
            return records
        }
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord {
            restoreCalls += 1; XCTAssertEqual(identity.scope, .personal); duringRestore?()
            if let failure { throw failure }
            if pauseRestore { return try await withCheckedThrowingContinuation { restoreWait = $0 } }
            return try XCTUnwrap(restored ?? records.first { $0.id == id })
        }
    }
    private func browser(_ reader: Reader, current: RuntimeDependencyContext? = nil) throws -> OwnerDraftBrowser {
        let c = try current ?? context()
        return OwnerDraftBrowser(reader: reader, lease: .init(context: c, current: { c }))
    }
    func testListsBothTypesAndRestoresLatestMetadataWithoutPayloadAdapter() async throws {
        let r = Reader(); r.records = [try record(), try record(id: 12, type: "TOPIC")]
        r.restored = try record(version: 3)
        let b = try browser(r); await b.load()
        XCTAssertEqual(b.phase, .ready); XCTAssertEqual(b.rows.map(\.businessType), [.activity, .topic])
        await b.restore(id: 11)
        XCTAssertEqual(b.detail?.version, 3); XCTAssertEqual(b.detail?.savedTime, "2026-10-03T08:00:00+08:00")
        XCTAssertEqual(r.listCalls, 1); XCTAssertEqual(r.restoreCalls, 1)
    }
    func testEmptyRefreshAndRetryReplaceOldList() async throws {
        let r = Reader(), b = try browser(r)
        await b.load(); XCTAssertEqual(b.phase, .empty)
        r.records = [try record()]; await b.load(); XCTAssertEqual(b.rows.count, 1)
        r.failure = .unavailable; await b.load(); XCTAssertEqual(b.phase, .failed); XCTAssertTrue(b.rows.isEmpty)
        r.failure = nil; await b.load(); XCTAssertEqual(b.phase, .ready)
    }
    func testDuplicateAndWrongOwnerRowsFailClosed() async throws {
        for records in [[try record(), try record()], [try record(owner: 8)]] {
            let r = Reader(); r.records = records; let b = try browser(r); await b.load()
            XCTAssertEqual(b.phase, .failed); XCTAssertTrue(b.rows.isEmpty)
        }
    }
    func testRestoreRejectsWrongIDKeyAndVersionRollback() async throws {
        for restored in [try record(id: 99), try record(key: "different"), try record(version: 1)] {
            let r = Reader(); r.records = [try record()]; r.restored = restored
            let b = try browser(r); await b.load(); await b.restore(id: 11)
            XCTAssertNil(b.detail); XCTAssertEqual(b.detailIssue, .malformed)
        }
    }
    func testCannotRestoreArbitraryIDNotInOwnerList() async throws {
        let r = Reader(), b = try browser(r); await b.load(); await b.restore(id: 99)
        XCTAssertEqual(r.restoreCalls, 0)
    }
    func testUnsupportedDateEncodingRemainsUnavailable() throws {
        let times: [Any] = [123456, "<b>unsafe</b>", String(repeating: "x", count: 80),
                            "2026-10-03T08:00:00Z\n", "2026-10-03T08:00:00Z\r\n",
                            "2026-10-03T08:00:00Z\u{2028}", "2026-10-03T08:00:00Z\u{0000}"]
        for time in times {
            XCTAssertNil(try record(time: time).updateTime?.display)
        }
        XCTAssertNil(try record(time: nil).updateTime)
    }
    func testServerDateStringShapesArePreservedWithoutClockInterpretation() throws {
        for time in ["2026-10-03T08:00:00.000+08:00", "2026-10-03T00:00:00.000+0000",
                     "2026-10-03T00:00:00Z", "2026-10-03 08:00:00"] {
            XCTAssertEqual(try record(time: time).updateTime?.display, time)
        }
    }
    func testOptionalDisplayTimeKeepsCodableRoundTripsStable() throws {
        let times: [Any] = [123456, "2026-10-03T08:00:00+08:00", "unrecognized", ["unexpected": "object"]]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for time in times {
            let original = try record(time: time), bytes = try encoder.encode(original)
            let decoded = try JSONDecoder().decode(ContentDraftRecord.self, from: bytes)
            XCTAssertEqual(try encoder.encode(decoded), bytes)
            XCTAssertEqual(original, decoded)
        }
    }
    func testOptionalTimePreservesBinaryPlistMutationAndLegacyBaseline() throws {
        let identity = try ContentDraftIdentity(ownerMemberID: 7, businessType: .activity, clientDraftKey: "synthetic")
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()
        let times: [Any] = ["2026-10-03T08:00:00.000+08:00", 123456, ["unexpected": "object"]]
        for time in times {
            let baseline = try record(time: time)
            let mutation = try ContentDraftMutation.delete(identity: identity, baseline: baseline)
            let bytes = try encoder.encode(mutation)
            let decoded = try decoder.decode(ContentDraftMutation.self, from: bytes)
            try decoded.validate()
            XCTAssertEqual(decoded, mutation)
            XCTAssertEqual(decoded.baseline?.updateTime?.display, baseline.updateTime?.display)
            XCTAssertEqual(decoded.command, mutation.command)

            // Durable ciphertexts written before this optional field must still reopen.
            var legacy = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
            var oldBaseline = try XCTUnwrap(legacy["baseline"] as? [String: Any])
            oldBaseline.removeValue(forKey: "updateTime"); legacy["baseline"] = oldBaseline
            let oldBytes = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
            let restoredLegacy = try decoder.decode(ContentDraftMutation.self, from: oldBytes)
            try restoredLegacy.validate()
            XCTAssertEqual(restoredLegacy, mutation)
            XCTAssertNil(restoredLegacy.baseline?.updateTime)
            XCTAssertEqual(restoredLegacy.command, mutation.command)
        }
    }
    func testRoleAndRealmChangesDropLateListBeforeDisplay() async throws {
        for changed in [try context(role: "merchant"), try context(realm: "new-realm"), try context(account: 8)] {
            let original = try context(); var current = original
            let r = Reader(); r.records = [try record()]; r.duringList = { current = changed }
            let b = OwnerDraftBrowser(reader: r, lease: .init(context: original, current: { current }))
            await b.load(); XCTAssertEqual(b.phase, .invalidated); XCTAssertTrue(b.rows.isEmpty)
        }
    }
    func testExplicitHostRevocationRejectsABAEvenWhenContextMatchesAgain() async throws {
        let r = Reader(); r.records = [try record()]; let b = try browser(r)
        r.duringList = { b.invalidate() }
        await b.load(); await b.load(); XCTAssertEqual(b.phase, .invalidated); XCTAssertEqual(r.listCalls, 1)
    }
    func testLateRestoreCannotRepopulateAfterBack() async throws {
        let r = Reader(); r.records = [try record()]; let b = try browser(r); await b.load()
        r.duringRestore = { b.closeDetail() }
        await b.restore(id: 11); XCTAssertNil(b.detail); XCTAssertFalse(b.detailLoading)
        r.duringRestore = nil; await b.restore(id: 11); XCTAssertEqual(b.detail?.id, 11)
    }
    func testLateRestoreErrorCannotLeakAfterBack() async throws {
        let r = Reader(); r.records = [try record()]; let b = try browser(r); await b.load()
        r.failure = .unauthorized; r.duringRestore = { b.closeDetail() }
        await b.restore(id: 11); XCTAssertNil(b.detailIssue)
    }
    func testListRefreshClearsOpenDetail() async throws {
        let r = Reader(); r.records = [try record()]; let b = try browser(r); await b.load(); await b.restore(id: 11)
        r.duringList = { XCTAssertNil(b.detail); XCTAssertEqual(b.phase, .loading) }
        await b.load(); XCTAssertNil(b.detail)
    }
    func testOverlappingListDoesNotDispatchTwice() async throws {
        let r = Reader(); r.records = [try record()]; r.pauseList = true
        let b = try browser(r), started = expectation(description: "list started")
        r.duringList = { started.fulfill() }
        let task = Task { await b.load() }; await fulfillment(of: [started], timeout: 2)
        await b.load(); XCTAssertEqual(r.listCalls, 1); XCTAssertEqual(b.phase, .loading)
        r.listWait?.resume(returning: r.records); r.listWait = nil; await task.value
        XCTAssertEqual(b.phase, .ready)
    }
    func testBackReopenStartsFreshListAndRejectsRetiredSuccessAndError() async throws {
        for lateFailure in [false, true] {
            let r = Reader(), oldRecord = try record()
            r.records = [oldRecord]; r.pauseList = true
            let b = try browser(r), started = expectation(description: "retired list suspended")
            r.duringList = { started.fulfill() }
            let task = Task { await b.load() }; await fulfillment(of: [started], timeout: 2)
            let retired = try XCTUnwrap(r.listWait); r.listWait = nil
            b.closeList(); XCTAssertEqual(b.phase, .idle); XCTAssertTrue(b.rows.isEmpty)
            r.pauseList = false; r.duringList = nil; r.records = [try record(id: 12, type: "TOPIC")]
            await b.load()
            XCTAssertEqual(r.listCalls, 2); XCTAssertEqual(b.rows.map(\.id), [12])
            if lateFailure { retired.resume(throwing: ContentDraftIssue.unavailable) }
            else { retired.resume(returning: [oldRecord]) }
            await task.value
            XCTAssertEqual(b.phase, .ready); XCTAssertEqual(b.rows.map(\.id), [12]); XCTAssertNil(b.issue)
        }
    }
    func testClosingListClearsMetadataWithoutRevivingInvalidatedBrowser() async throws {
        let r = Reader(); r.records = [try record()]; let b = try browser(r)
        await b.load(); await b.restore(id: 11); b.closeList()
        XCTAssertEqual(b.phase, .idle); XCTAssertTrue(b.rows.isEmpty); XCTAssertNil(b.detail)
        b.invalidate(); b.closeList(); await b.load()
        XCTAssertEqual(b.phase, .invalidated); XCTAssertEqual(b.issue, .staleSession); XCTAssertEqual(r.listCalls, 1)
    }
    func testNewerDetailWinsOverLateOlderRestore() async throws {
        let r = Reader(); r.records = [try record(), try record(id: 12, type: "TOPIC")]
        let b = try browser(r); await b.load(); r.pauseRestore = true
        let started = expectation(description: "restore started"); r.duringRestore = { started.fulfill() }
        let task = Task { await b.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
        r.pauseRestore = false; r.duringRestore = nil; await b.restore(id: 12)
        XCTAssertEqual(b.detail?.id, 12)
        r.restoreWait?.resume(returning: try record()); r.restoreWait = nil; await task.value
        XCTAssertEqual(b.detail?.id, 12)
    }
    func testReadApprovalRejectsMerchantForeignOwnerAndMutationRoutes() throws {
        let c = try context()
        let merchant = try ContentDraftRouteGrant(context: c, ownerMemberID: 8, scope: .merchant, routes: [.list, .restore], expiresAt: .distantFuture)
        XCTAssertThrowsError(try OwnerDraftReadApproval(grant: merchant))
        let writes = try ContentDraftRouteGrant(context: c, ownerMemberID: 7, scope: .personal, routes: [.list, .restore, .save], expiresAt: .distantFuture)
        XCTAssertThrowsError(try OwnerDraftReadApproval(grant: writes))
        let approved = try OwnerDraftReadApproval(grant: .init(context: c, ownerMemberID: 7, scope: .personal, routes: [.list, .restore], expiresAt: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(approved.matches(c, now: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(approved.matches(c, now: Date(timeIntervalSince1970: 200)))
        XCTAssertFalse(approved.matches(try context(role: "merchant"), now: Date(timeIntervalSince1970: 100)))
    }
}
