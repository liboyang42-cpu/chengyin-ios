import XCTest
@testable import QuestifyCore

/// Independent, synthetic adversarial probes. Apple execution is required separately.
@MainActor final class InstalledDraftReceiptReviewTests: XCTestCase {
    private func receipt() -> [String: Any] {
        ["installationId": 701, "targetDraftId": 11, "installedTargetVersion": 2,
         "installedAt": "2026-10-03T00:00:00Z", "versionId": "synthetic-version",
         "contentHash": String(repeating: "a", count: 64), "termsHash": String(repeating: "b", count: 64),
         "installedTargetPayloadHash": ContentDraftRecord.hash("{}"),
         "binding": "EXACT_REVISION", "evidenceKind": "HISTORICAL_INSTALLATION"]
    }
    private func modules() -> [String: Any] {
        ["availability": "HISTORICAL_RECEIPTS_ONLY", "receipts": [receipt()], "hasMore": false,
         "contentUseStatus": "POST_INSTALL_POLICY_UNAVAILABLE", "textPreviewAllowed": false,
         "editingAllowed": false, "exportAllowed": false, "publicationAllowed": false,
         "executionAllowed": false, "commercialUseAllowed": false]
    }
    private func wire(_ modules: Any? = nil, owner: Int = 7, version: Int = 2) -> [String: Any] {
        var value: [String: Any] = ["id": 11, "ownerMemberId": owner, "businessType": "TOPIC", "clientDraftKey": "synthetic",
            "payloadJson": "{}", "payloadHash": ContentDraftRecord.hash("{}"), "status": "DRAFT", "version": version,
            "updatedByDevice": "synthetic"]
        if let modules { value["installedModules"] = modules }; return value
    }
    private func decode(_ object: [String: Any]) throws -> ContentDraftRecord {
        try JSONDecoder().decode(ContentDraftRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func summary(_ object: [String: Any]) throws -> OwnerDraftInstalledReceipts {
        OwnerDraftInstalledReceipts(record: try decode(object))
    }
    private func context() throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://fixture.invalid")!, role: "player",
              session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"))
    }
    private func identity() throws -> ContentDraftIdentity {
        try .init(ownerMemberID: 7, businessType: .topic, clientDraftKey: "synthetic")
    }
    func testUnavailableStatesCannotHideCapabilityOrBindingEscalation() throws {
        for availability in ["NOT_ENABLED", "OWNER_ONLY"] {
            for flag in ["textPreviewAllowed", "editingAllowed", "exportAllowed", "publicationAllowed", "executionAllowed", "commercialUseAllowed"] {
                var value = modules(); value["availability"] = availability; value["receipts"] = [[String: Any]]()
                XCTAssertEqual(try summary(wire(value)).state.rawValue, availability == "NOT_ENABLED" ? "notEnabled" : "ownerOnly")
                value[flag] = true
                XCTAssertEqual(try summary(wire(value)).state, .invalid)
            }
        }
    }
    func testMalformedTailInvalidatesWholeHistoryRatherThanKeepingTrustedPrefix() throws {
        var bad = receipt(); bad["installationId"] = 702; bad["termsHash"] = "bad"
        var value = modules(); value["receipts"] = [receipt(), bad]
        let projection = try summary(wire(value))
        XCTAssertEqual(projection.state, .invalid); XCTAssertTrue(projection.rows.isEmpty); XCTAssertFalse(projection.hasMore)
    }
    func testReceiptNumericBooleansStringsAndOverflowDoNotBecomeIdentities() throws {
        for key in ["installationId", "targetDraftId", "installedTargetVersion"] {
            for value: Any in [true, false, "11", NSNull(), 1.5, UInt64.max] {
                var row = receipt(); row[key] = value
                var object = modules(); object["receipts"] = [row]
                XCTAssertEqual(try summary(wire(object)).state, .invalid, key)
            }
        }
    }
    func testVersionLimitIsUTF16AndFiftyDoesNotRequireHasMore() throws {
        var row = receipt(); row["versionId"] = String(repeating: "\u{1F310}", count: 256)
        var object = modules(); object["receipts"] = [row]
        XCTAssertEqual(try summary(wire(object)).state, .historical)
        row["versionId"] = String(repeating: "\u{1F310}", count: 257); object["receipts"] = [row]
        XCTAssertEqual(try summary(wire(object)).state, .invalid)
        object["receipts"] = (1...50).map { index -> [String: Any] in
            var row = receipt(); row["installationId"] = index; return row
        }
        let page = try summary(wire(object)); XCTAssertEqual(page.rows.count, 50); XCTAssertFalse(page.hasMore)
    }

    // Frozen native pre-extension record field order, with synthesized Codable encoding.
    // This is not a second implementation of the private receipt contract.
    private struct LegacyRecord: Codable {
        let id: Int64
        let ownerMemberId: Int64
        let businessType: ContentDraftBusinessType
        let clientDraftKey: String
        let subjectId: Int64?
        let payloadJson: String
        let payloadHash: String
        let status: ContentDraftRecord.Status
        let version: Int64
        let updatedByDevice: String
        let publishedResourceId: Int64?
        let updateTime: ContentDraftServerTime?
    }
    private struct LegacyMutation: Codable {
        let operationID: UUID
        let identity: ContentDraftIdentity
        let kind: ContentDraftMutation.Kind
        let command: ContentDraftMutation.Command
        let baseline: LegacyRecord?
    }
    func testFrozenSynthesizedLegacyEncodingMatchesRecordAndWholeMutationBytes() throws {
        let subjects: [Int64?] = [nil, 42]
        let times: [String?] = [nil, "2026-10-03T00:00:00Z"]
        let json = JSONEncoder(); json.outputFormatting = [.sortedKeys]
        let plist = PropertyListEncoder(); plist.outputFormat = .binary
        for subject in subjects { for time in times {
            var object = wire(modules()); object["subjectId"] = subject; object["updateTime"] = time
            let data = try JSONSerialization.data(withJSONObject: object)
            let legacy = try JSONDecoder().decode(LegacyRecord.self, from: data)
            let current = try decode(object)
            XCTAssertEqual(try json.encode(legacy), try json.encode(current))
            XCTAssertEqual(try plist.encode(legacy), try plist.encode(current))
            let mutation = try ContentDraftMutation.delete(identity: identity(), baseline: current)
            let oldMutation = LegacyMutation(operationID: mutation.operationID, identity: mutation.identity,
                kind: mutation.kind, command: mutation.command, baseline: legacy)
            let oldBytes = try plist.encode(oldMutation)
            XCTAssertEqual(oldBytes, try plist.encode(mutation))
            let reopened = try PropertyListDecoder().decode(ContentDraftMutation.self, from: oldBytes)
            try reopened.validate(); XCTAssertEqual(reopened, mutation)
            XCTAssertNil(reopened.baseline?.installedModules)
            XCTAssertEqual(try plist.encode(reopened), oldBytes)
        } }
    }
    func testNestedUnknownDataNeverEntersProjectionJournalOrRecordDescription() throws {
        var row = receipt(); row["source"] = ["text": "private-source-sentinel", "url": "https://private.invalid"]
        var value = modules(); value["receipts"] = [row]; value["rights"] = ["commercial": true, "expiry": "private-rights-sentinel"]
        let current = try decode(wire(value)), projection = OwnerDraftInstalledReceipts(record: current)
        XCTAssertEqual(projection.state, .historical)
        for text in [String(describing: current), String(reflecting: current), String(describing: projection),
                     String(decoding: try JSONEncoder().encode(current), as: UTF8.self)] {
            XCTAssertFalse(text.contains("sentinel")); XCTAssertFalse(text.contains("private.invalid"))
        }
        let baseline = try decode(wire())
        XCTAssertEqual(current, baseline)
    }
    func testDuplicateKnownAndUnknownReceiptKeysRejectWholeHTTPEnvelope() async throws {
        let context = try context(), lease = ContentDraftSessionLease(context: context, current: { context })
        let transport = ContentDraftRecordingTransport()
        let grant = try ContentDraftRouteGrant(context: context, ownerMemberID: 7, scope: .personal,
            routes: [.restore], expiresAt: .distantFuture)
        let service = ContentDraftService(api: try .init(baseURL: context.baseURL), transport: transport, lease: lease, grant: grant)
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": wire(modules())], options: [.sortedKeys])
        let original = String(decoding: data, as: UTF8.self)
        for altered in [original.replacingOccurrences(of: "\"installationId\":701", with: "\"installationId\":701,\"installationId\":702"),
                        original.replacingOccurrences(of: "\"installationId\":701", with: "\"installationId\":701,\"private\":1,\"private\":2")] {
            XCTAssertNotEqual(altered, original); transport.response = (Data(altered.utf8), 200)
            do { _ = try await service.restore(id: 11, identity: identity()); XCTFail("Accepted ambiguous receipt envelope") }
            catch { XCTAssertEqual(error as? ContentDraftIssue, .malformed) }
        }
        XCTAssertEqual(transport.requests.count, 2)
    }
    private final class Reader: ContentDraftReading {
        var current: ContentDraftRecord
        var paused = false
        var wait: CheckedContinuation<ContentDraftRecord, Error>?
        var started: (() -> Void)?
        init(_ value: ContentDraftRecord) { current = value }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { [current] }
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord {
            if paused { return try await withCheckedThrowingContinuation { wait = $0; started?() } }; return current
        }
    }
    private func browser(_ reader: Reader) throws -> OwnerDraftBrowser {
        let context = try context()
        return OwnerDraftBrowser(reader: reader, lease: .init(context: context, current: { context }))
    }
    func testReceiptMetadataCannotMaskForeignOwnerOrRegressingDraft() async throws {
        for record in [try decode(wire(modules(), owner: 8)), try decode(wire(modules(), version: 1))] {
            let reader = Reader(try decode(wire())), browser = try browser(reader)
            await browser.load(); reader.current = record; await browser.restore(id: 11)
            XCTAssertNil(browser.detail); XCTAssertEqual(browser.detailIssue, .malformed)
        }
    }
    func testListBackReopenAndNewRestoreRetireBothLateSuccessAndLateFailure() async throws {
        for failure in [false, true] {
            let reader = Reader(try decode(wire(modules()))), browser = try browser(reader)
            await browser.load(); reader.paused = true
            let started = expectation(description: "retired restore"); reader.started = { started.fulfill() }
            let task = Task { await browser.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
            browser.closeDetail(); browser.closeList(); reader.paused = false
            var empty = modules(); empty["receipts"] = [[String: Any]](); reader.current = try decode(wire(empty))
            await browser.load(); await browser.restore(id: 11)
            if failure { reader.wait?.resume(throwing: ContentDraftIssue.unauthorized) }
            else { reader.wait?.resume(returning: try decode(wire(modules()))) }
            reader.wait = nil; await task.value
            XCTAssertEqual(browser.phase, .ready); XCTAssertNil(browser.detailIssue)
            XCTAssertEqual(browser.detail?.installedReceipts?.state, .historical)
            XCTAssertTrue(try XCTUnwrap(browser.detail?.installedReceipts?.rows).isEmpty)
        }
    }
}
