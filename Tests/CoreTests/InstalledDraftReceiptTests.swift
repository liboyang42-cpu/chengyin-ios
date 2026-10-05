import XCTest
@testable import QuestifyCore

@MainActor final class InstalledDraftReceiptTests: XCTestCase {
    private func receipt(id: Int64 = 701, target: Int64 = 11, version: Int64 = 2,
                         hash: Any = ContentDraftRecord.hash("{}"), binding: String = "EXACT_REVISION") -> [String: Any] {
        ["installationId": id, "targetDraftId": target, "installedTargetVersion": version,
         "installedAt": "2026-10-03T00:00:00.123456789Z", "versionId": "synthetic-module-version",
         "contentHash": String(repeating: "a", count: 64), "termsHash": String(repeating: "b", count: 64),
         "installedTargetPayloadHash": hash, "binding": binding, "evidenceKind": "HISTORICAL_INSTALLATION"]
    }
    private func modules(_ rows: [[String: Any]]? = nil, availability: String = "HISTORICAL_RECEIPTS_ONLY", more: Bool = false) -> [String: Any] {
        ["availability": availability, "receipts": rows ?? [receipt()], "hasMore": more,
         "contentUseStatus": "POST_INSTALL_POLICY_UNAVAILABLE", "textPreviewAllowed": false, "editingAllowed": false,
         "exportAllowed": false, "publicationAllowed": false, "executionAllowed": false, "commercialUseAllowed": false]
    }
    private func record(_ modules: Any? = nil, id: Int64 = 11, owner: Int64 = 7, version: Int64 = 2) throws -> ContentDraftRecord {
        var object: [String: Any] = ["id": id, "ownerMemberId": owner, "businessType": "TOPIC", "clientDraftKey": "synthetic",
            "payloadJson": "{}", "payloadHash": ContentDraftRecord.hash("{}"), "status": "DRAFT", "version": version,
            "updatedByDevice": "synthetic", "updateTime": "2026-10-03T00:00:00Z"]
        if let modules { object["installedModules"] = modules }
        return try JSONDecoder().decode(ContentDraftRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func projection(_ modules: Any?) throws -> OwnerDraftInstalledReceipts { OwnerDraftInstalledReceipts(record: try record(modules)) }
    func testOmissionEmptyDisabledAndOwnerOnlyAreDistinct() throws {
        XCTAssertEqual(try projection(nil).state, .omitted)
        XCTAssertEqual(try projection(modules([])).state, .historical)
        XCTAssertTrue(try projection(modules([])).rows.isEmpty)
        XCTAssertEqual(try projection(modules([], availability: "NOT_ENABLED")).state, .notEnabled)
        XCTAssertEqual(try projection(modules([], availability: "OWNER_ONLY")).state, .ownerOnly)
    }
    func testNullWrongTypeUnknownAvailabilityAndUnknownBindingStayInvalid() throws {
        var unknownBinding = receipt(); unknownBinding["binding"] = "PERPETUAL_USE"
        let invalid: [Any] = [NSNull(), "unexpected", [Any](), modules(availability: "ACTIVE_LICENSE"), modules([unknownBinding])]
        for value in invalid {
            XCTAssertEqual(try projection(value).state, .invalid)
            XCTAssertTrue(try projection(value).rows.isEmpty)
        }
    }
    func testEachCapabilityMustBePresentBooleanFalseAndPolicyExact() throws {
        for flag in ["textPreviewAllowed", "editingAllowed", "exportAllowed", "publicationAllowed", "executionAllowed", "commercialUseAllowed"] {
            let invalid: [Any] = [true, 0, "false", NSNull()]
            for value in invalid {
                var response = modules(); response[flag] = value
                XCTAssertEqual(try projection(response).state, .invalid, flag)
            }
            var missing = modules(); missing.removeValue(forKey: flag)
            XCTAssertEqual(try projection(missing).state, .invalid, flag)
        }
        var changed = modules(); changed["contentUseStatus"] = "ALLOWED"
        XCTAssertEqual(try projection(changed).state, .invalid)
    }
    func testExactStaleAndUnverifiableBindingsStayHistorical() throws {
        for (row, binding) in [(receipt(), InstalledDraftModules.Binding.exact),
                               (receipt(version: 1, binding: "STALE_BINDING"), .stale),
                               (receipt(hash: String(repeating: "d", count: 64), binding: "STALE_BINDING"), .stale),
                               (receipt(hash: NSNull(), binding: "BINDING_UNVERIFIABLE"), .unverifiable)] {
            let summary = try projection(modules([row]))
            XCTAssertEqual(summary.state, .historical); XCTAssertEqual(summary.rows.first?.binding, binding)
            XCTAssertEqual(summary.rows.first?.installedTime, "2026-10-03T00:00:00.123456789Z")
        }
    }
    func testWrongTargetAndContradictoryBindingCannotAttachToDraft() throws {
        for row in [receipt(target: 12), receipt(version: 1), receipt(hash: String(repeating: "d", count: 64)),
                    receipt(binding: "STALE_BINDING"), receipt(binding: "BINDING_UNVERIFIABLE"),
                    receipt(hash: NSNull()), receipt(hash: "bad", binding: "STALE_BINDING")] {
            XCTAssertEqual(try projection(modules([row])).state, .invalid)
        }
    }
    func testStrictReceiptCapDuplicateIdentityAndHasMoreShape() throws {
        let fifty = (1...50).map { receipt(id: Int64($0)) }
        let capped = try projection(modules(fifty, more: true))
        XCTAssertEqual(capped.rows.count, 50); XCTAssertTrue(capped.hasMore)
        for response in [modules(fifty + [receipt(id: 51)], more: true), modules([receipt(), receipt()]),
                         modules([], more: true), modules(more: true), modules(availability: "NOT_ENABLED"),
                         modules(availability: "OWNER_ONLY"), modules([], availability: "NOT_ENABLED", more: true)] {
            XCTAssertEqual(try projection(response).state, .invalid)
        }
    }
    func testInvalidIDsHashesEvidenceAndOversizedVersionAreRejected() throws {
        let invalid: [(String, Any)] = [("installationId", 0), ("targetDraftId", -1), ("installedTargetVersion", 0),
            ("versionId", String(repeating: "x", count: 513)), ("versionId", ""), ("contentHash", String(repeating: "A", count: 64)),
            ("termsHash", String(repeating: "b", count: 65)), ("evidenceKind", "LICENSE")]
        for (key, value) in invalid {
            var row = receipt(); row[key] = value
            XCTAssertEqual(try projection(modules([row])).state, .invalid, key)
        }
    }
    func testEveryReceiptFieldAndTopLevelFieldMustBePresent() throws {
        for key in receipt().keys {
            var row = receipt(); row.removeValue(forKey: key)
            XCTAssertEqual(try projection(modules([row])).state, .invalid, key)
        }
        for key in modules().keys {
            var response = modules(); response.removeValue(forKey: key)
            XCTAssertEqual(try projection(response).state, .invalid, key)
        }
    }
    func testTimestampIsBoundedUTCDisplayAndNeverAClockOrRight() throws {
        let invalid: [Any] = [12345, "<img src=x>", "2026-10-03T00:00:00Z\n", "2026-10-03T00:00:00Z\u{2028}", String(repeating: "x", count: 41)]
        for time in invalid {
            var row = receipt(); row["installedAt"] = time
            XCTAssertEqual(try projection(modules([row])).state, .invalid)
        }
        for time in ["2026-10-03T00:00:00Z", "2026-10-03T00:00:00.123Z", "2026-10-03T00:00:00.123456Z"] {
            var row = receipt(); row["installedAt"] = time
            XCTAssertEqual(try projection(modules([row])).rows.first?.installedTime, time)
        }
    }
    func testUnknownPrivateExtensionsNeverReachUIProjectionOrEncoding() throws {
        var row = receipt(); row["sourceText"] = "private-text-sentinel"; row["seller"] = "private-seller-sentinel"
        var response = modules([row]); response["rightsJson"] = "private-rights-sentinel"
        let value = try record(response), summary = OwnerDraftInstalledReceipts(record: value)
        XCTAssertEqual(summary.rows.first?.id, 701)
        XCTAssertFalse(String(describing: summary).contains("sentinel"))
        let encoded = try JSONEncoder().encode(value)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("sentinel"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("installedModules"))
    }
    func testMetadataDoesNotChangeLegacyRecordEncodingEqualityPayloadOrMutation() throws {
        let original = try record(), enriched = try record(modules())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(original, enriched)
        XCTAssertEqual(try encoder.encode(original), try encoder.encode(enriched))
        XCTAssertEqual(original.payloadHash, enriched.payloadHash)
        let identity = try ContentDraftIdentity(ownerMemberID: 7, businessType: .topic, clientDraftKey: "synthetic")
        let mutation = try ContentDraftMutation.delete(identity: identity, baseline: enriched)
        let pending = ContentDraftPending(mutation: mutation)
        let plist = PropertyListEncoder(); plist.outputFormat = .binary
        let bytes = try plist.encode(pending)
        let reopened = try PropertyListDecoder().decode(ContentDraftPending.self, from: bytes)
        try reopened.mutation.validate()
        XCTAssertEqual(reopened, pending)
        XCTAssertNil(reopened.mutation.baseline?.installedModules)
        XCTAssertEqual(try encoder.encode(reopened), try encoder.encode(pending))
        XCTAssertEqual(try plist.encode(reopened), bytes)
    }
    func testAsyncDurableJournalReopensAndCASRetainsCallerHeldReceiptFreeSnapshot() async throws {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://fixture.invalid")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"))
        let identity = try ContentDraftIdentity(ownerMemberID: 7, businessType: .topic, clientDraftKey: "synthetic")
        let scope = ContentDraftJournalScope(context: context, identity: identity)
        let anchors = ContentDraftDurableJournalTests.Anchors(), blobs = ContentDraftDurableJournalTests.Blobs()
        let journal = try ContentDraftDurableJournal(scope: scope, anchors: anchors, ciphertexts: blobs)
        let pending = ContentDraftPending(mutation: try .delete(identity: identity, baseline: record(modules())))
        let snapshot = try await journal.insert(pending)
        XCTAssertEqual(snapshot.value, pending)
        let reopened = try ContentDraftDurableJournal(scope: scope, anchors: anchors, ciphertexts: blobs)
        let restored = try await reopened.read()
        XCTAssertEqual(restored, snapshot)
        XCTAssertNil(restored?.value.mutation.baseline?.installedModules)
        let dispatched = ContentDraftPending(mutation: pending.mutation, dispatched: true)
        let dispatchedSnapshot = try await reopened.replace(snapshot, with: dispatched)
        do { try await journal.clear(matching: snapshot); XCTFail("Stale snapshot cleared a newer generation") }
        catch { XCTAssertEqual(error as? ContentDraftIssue, .storageUnavailable) }
        try await reopened.clear(matching: dispatchedSnapshot)
        let empty = try await reopened.read(); XCTAssertNil(empty)
    }
    private final class Reader: ContentDraftReading {
        var listRecord: ContentDraftRecord
        var restoreRecord: ContentDraftRecord
        var wait: CheckedContinuation<ContentDraftRecord, Error>?
        var onStart: (() -> Void)?
        var pause = false
        init(_ record: ContentDraftRecord) { listRecord = record; restoreRecord = record }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { [listRecord] }
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord {
            if pause { return try await withCheckedThrowingContinuation { wait = $0; onStart?() } }
            return restoreRecord
        }
    }
    private func browser(_ reader: Reader) throws -> OwnerDraftBrowser {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://fixture.invalid")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"))
        return OwnerDraftBrowser(reader: reader, lease: .init(context: context, current: { context }))
    }
    func testListNeverProjectsReceiptsAndDetailUsesFreshRestoreRevision() async throws {
        let reader = Reader(try record(modules())), browser = try browser(reader)
        await browser.load(); XCTAssertNil(browser.rows.first?.installedReceipts)
        reader.restoreRecord = try record(modules([receipt(binding: "STALE_BINDING")]), version: 3)
        await browser.restore(id: 11)
        XCTAssertEqual(browser.detail?.version, 3)
        XCTAssertEqual(browser.detail?.installedReceipts?.rows.first?.binding, .stale)
        browser.closeDetail(); XCTAssertNil(browser.detail)
    }
    func testBackCancelAndInvalidationSuppressLateReceipts() async throws {
        for action in ["back", "cancel", "session"] {
            let reader = Reader(try record(modules())), browser = try browser(reader)
            await browser.load(); reader.pause = true
            let started = expectation(description: action); reader.onStart = { started.fulfill() }
            let task = Task { await browser.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
            switch action {
            case "back": browser.closeDetail()
            case "cancel": task.cancel()
            default: browser.invalidate()
            }
            reader.wait?.resume(returning: reader.restoreRecord); reader.wait = nil; await task.value
            XCTAssertNil(browser.detail); XCTAssertFalse(browser.detailLoading)
            if action != "session" {
                reader.pause = false; await browser.restore(id: 11)
                XCTAssertEqual(browser.detail?.installedReceipts?.rows.count, 1)
            } else { XCTAssertEqual(browser.phase, .invalidated) }
        }
    }
    func testNewerRestoreCannotBeOverwrittenByRetiredReceiptResponse() async throws {
        let reader = Reader(try record(modules())), browser = try browser(reader)
        await browser.load(); reader.pause = true
        let started = expectation(description: "old receipt restore"); reader.onStart = { started.fulfill() }
        let task = Task { await browser.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
        reader.pause = false; reader.restoreRecord = try record(modules([]))
        await browser.restore(id: 11)
        reader.wait?.resume(returning: try record(modules())); reader.wait = nil; await task.value
        XCTAssertEqual(browser.detail?.installedReceipts?.state, .historical)
        XCTAssertEqual(browser.detail?.installedReceipts?.rows.count, 0)
    }
    func testMalformedMetadataKeepsValidatedDraftMetadataAvailable() async throws {
        let reader = Reader(try record(modules(availability: "UNKNOWN"))), browser = try browser(reader)
        await browser.load(); await browser.restore(id: 11)
        XCTAssertEqual(browser.detail?.id, 11); XCTAssertNil(browser.detailIssue)
        XCTAssertEqual(browser.detail?.installedReceipts?.state, .invalid)
    }
}
