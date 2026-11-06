import XCTest
@testable import Questify

/// NOT_RUN. Real journal adapter and coordinator over synthetic storage/service only.
/// Valid alternate records are test-injected, not a claim that the OS changed a stored label.
@MainActor final class PrivateHomeExactLabelRecoveryJourneyTests: XCTestCase {
    private actor Vault: PrivateHomeKeychainPrimitive {
        var items: [String: PrivateHomeKeychainItem] = [:]
        var removes = 0, inserts = 0
        func read(key: String) -> PrivateHomeKeychainItem? { items[key] }
        func insert(key: String, item: PrivateHomeKeychainItem) -> Bool {
            inserts += 1
            guard items[key] == nil else { return false }; items[key] = item; return true
        }
        func remove(key: String, matchingTag: Data) -> Bool {
            removes += 1
            guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
        }
        func snapshot() -> [String: PrivateHomeKeychainItem] { items }
        func replace(_ snapshot: [String: PrivateHomeKeychainItem]) { items = snapshot }
    }
    @MainActor private final class Service: PrivateHomeServing {
        var loads = 0, writes: [PrivateHomeMutation] = [], version: Int64 = 3
        var loseResponse = false
        var saved: PrivateHomeMutation?
        var beforeReceipt: (() async -> Void)?
        func load() throws -> PrivateHomeSnapshot {
            loads += 1
            var body: [String: Any] = ["version": version, "status": "DELETED"]
            if let saved, let label = saved.label, let latitude = saved.latitude, let longitude = saved.longitude {
                body = ["version": version, "status": "ACTIVE", "changedAt": 1, "effectiveAt": 1,
                        "label": label, "latitude": NSDecimalNumber(decimal: latitude),
                        "longitude": NSDecimalNumber(decimal: longitude), "datum": "WGS84"]
            }
            return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: JSONSerialization.data(withJSONObject: body))
        }
        func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
            writes.append(mutation); version = mutation.expectedVersion + 1; saved = mutation
            if let beforeReceipt { await beforeReceipt() }
            if loseResponse { throw PrivateHomeIssue.unknownOutcome }
            return .init(requestId: mutation.requestId, decision: mutation.method == "PUT" ? .saved : .deleted, version: version)
        }
    }
    @MainActor private final class Fixture {
        let scope: RegionalSessionStorageScope, owner: PlayExperienceSession
        let vault: Vault, journal: PrivateHomeKeychainJournal
        let service = Service()
        init() throws {
            let endpoint = "https://exact-label.example.test"
            let config = try RegionalConfiguration(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]])
            let scope = try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.exactLabel", realm: "synthetic")
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: scope.service, token: "synthetic-token")
            self.scope = scope; self.owner = owner
            let vault = Vault(); self.vault = vault
            journal = try .init(storageScope: scope, owner: owner, primitive: vault)
        }
        func model() -> PrivateHomeCoordinator {
            .init(service: service, journal: journal, owner: owner, enabled: true, current: { [owner] in owner })
        }
        /// Build a valid schema/fingerprint/tag through the original writer in an independent fake vault.
        func record(_ mutation: PrivateHomeMutation) async throws -> [String: PrivateHomeKeychainItem] {
            let other = Vault(), writer = try PrivateHomeKeychainJournal(storageScope: scope, owner: owner, primitive: other)
            try await writer.save(mutation); return await other.snapshot()
        }
    }
    private let pairs = [("Caf\u{00E9}", "Cafe\u{0301}"), ("\u{00C5}", "A\u{030A}"),
                         ("\u{AC00}", "\u{1100}\u{1161}"), ("a\u{0323}\u{0301}", "a\u{0301}\u{0323}")]
    private func mutation(_ label: String, id: String = "original-request") throws -> PrivateHomeMutation {
        try .init(requestId: id, expectedVersion: 3, label: label, point: .init(latitude: 12, longitude: 45))
    }
    private func sameBytes(_ a: [String: PrivateHomeKeychainItem], _ b: [String: PrivateHomeKeychainItem],
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(a.keys), Set(b.keys), file: file, line: line)
        for key in a.keys {
            XCTAssertEqual(a[key]?.bytes, b[key]?.bytes, file: file, line: line)
            XCTAssertEqual(a[key]?.tag, b[key]?.tag, file: file, line: line)
        }
    }
    private func labelBytes(_ actual: String?, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.map { Data($0.utf8) }, Data(expected.utf8), file: file, line: line)
    }
    private func unknown(_ model: PrivateHomeCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .unknown, file: file, line: line)
        XCTAssertFalse(model.canEdit, file: file, line: line); XCTAssertFalse(model.canConfirm, file: file, line: line)
        XCTAssertNil(model.decision, file: file, line: line)
    }

    func testDuplicateSaveCannotAcceptCanonicallyEquivalentDifferentPayload() async throws {
        for (a, b) in pairs {
            for labels in [(a, b), (b, a)] {
                let f = try Fixture(), first = try mutation(labels.0), changed = try mutation(labels.1)
                try await f.journal.save(first); let original = await f.vault.snapshot()
                do { try await f.journal.save(changed); XCTFail("Different wire label cannot resume original") }
                catch { XCTAssertEqual(error as? PrivateHomeIssue, .storageUnavailable) }
                let after = await f.vault.snapshot(); sameBytes(original, after)
                let recovered = try await f.journal.read(); labelBytes(recovered?.label, labels.0)
            }
        }
    }
    func testEquivalentTextCannotAuthorizeConditionalClearOfOriginalRecord() async throws {
        for (a, b) in pairs {
            let f = try Fixture(); try await f.journal.save(mutation(a)); let original = await f.vault.snapshot()
            do { try await f.journal.clear(matching: mutation(b)); XCTFail("Raw label must match before removal") }
            catch { XCTAssertEqual(error as? PrivateHomeIssue, .storageUnavailable) }
            let after = await f.vault.snapshot(), removes = await f.vault.removes
            sameBytes(original, after); XCTAssertEqual(removes, 0)
        }
    }
    func testExactLabelStillResumesAndClearsAfterAdapterRecreation() async throws {
        for (a, b) in pairs {
            for label in [a, b] {
                let f = try Fixture(), original = try mutation(label)
                try await f.journal.save(original); let bytes = await f.vault.snapshot()
                let reopened = try PrivateHomeKeychainJournal(storageScope: f.scope, owner: f.owner, primitive: f.vault)
                let recovered = try await reopened.read(); labelBytes(recovered?.label, label)
                try await reopened.save(original); let after = await f.vault.snapshot(); sameBytes(bytes, after)
                try await reopened.clear(matching: original); let empty = await f.vault.snapshot(); XCTAssertTrue(empty.isEmpty)
            }
        }
    }
    func testConcurrentEquivalentTextWritersHaveOnlyOneAcceptedOriginal() async throws {
        let f = try Fixture(), first = try mutation(pairs[0].0), second = try mutation(pairs[0].1)
        let other = try PrivateHomeKeychainJournal(storageScope: f.scope, owner: f.owner, primitive: f.vault)
        let a = Task { () -> Bool in do { try await f.journal.save(first); return true } catch { return false } }
        let b = Task { () -> Bool in do { try await other.save(second); return true } catch { return false } }
        let outcomes = await [a.value, b.value]
        XCTAssertEqual(outcomes.filter { $0 }.count, 1)
        let read = try await f.journal.read(), stored = try XCTUnwrap(read)
        XCTAssertEqual(stored, outcomes[0] ? first : second)
    }
    func testKnownUnknownRejectsEquivalentReplacementThenExplicitlyRecoversOriginal() async throws {
        for (a, b) in pairs {
            let f = try Fixture(), model = f.model()
            await model.load(); model.prepareSet(label: a, point: try .init(latitude: 12, longitude: 45))
            let original = try XCTUnwrap(model.review)
            f.service.loseResponse = true; await model.confirm(); unknown(model)
            let originalBytes = await f.vault.snapshot()
            let alternate = try await f.record(mutation(b, id: original.requestId)); await f.vault.replace(alternate)
            let reads = f.service.loads
            await model.load(); await model.retryExact(); unknown(model)
            XCTAssertEqual(model.issue, .storageUnavailable); XCTAssertEqual(f.service.loads, reads)
            XCTAssertEqual(f.service.writes.count, 1); let after = await f.vault.snapshot(); sameBytes(alternate, after)
            let removes = await f.vault.removes; XCTAssertEqual(removes, 0)
            // Test fixture restoration only. Product recovery must not reconstruct or overwrite bytes.
            await f.vault.replace(originalBytes); f.service.loseResponse = false
            await model.load(); unknown(model); XCTAssertEqual(f.service.writes.count, 1)
            await model.retryExact()
            XCTAssertEqual(f.service.writes.count, 2); labelBytes(f.service.writes.last?.label, a)
            XCTAssertEqual(model.decision, .saved); XCTAssertTrue(model.canEdit)
            let empty = await f.vault.snapshot(); XCTAssertTrue(empty.isEmpty)
        }
    }
    func testLateMatchingReceiptDoesNotClearValidDifferentLabelRecord() async throws {
        let f = try Fixture(), model = f.model(), a = pairs[0].0, b = pairs[0].1
        await model.load(); model.prepareSet(label: a, point: try .init(latitude: 12, longitude: 45))
        let original = try XCTUnwrap(model.review)
        let alternate = try await f.record(mutation(b, id: original.requestId))
        f.service.beforeReceipt = { await f.vault.replace(alternate) }
        await model.confirm(); unknown(model)
        XCTAssertEqual(f.service.writes.count, 1)
        let after = await f.vault.snapshot(), removes = await f.vault.removes
        sameBytes(alternate, after); XCTAssertEqual(removes, 0)
        await model.load(); unknown(model); XCTAssertEqual(model.issue, .storageUnavailable)
    }
    func testCompetingLabelDuringOriginalSaveDoesNotDispatchOrOverwrite() async throws {
        let f = try Fixture(), model = f.model(), a = pairs[0].0, b = pairs[0].1
        await model.load(); model.prepareSet(label: a, point: try .init(latitude: 12, longitude: 45))
        let original = try XCTUnwrap(model.review)
        let alternate = try await f.record(mutation(b, id: original.requestId)); await f.vault.replace(alternate)
        await model.confirm()
        XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.issue, .storageUnavailable)
        await model.load(); await model.retryExact(); unknown(model)
        XCTAssertEqual(f.service.writes.count, 0)
        let after = await f.vault.snapshot(), removes = await f.vault.removes
        sameBytes(alternate, after); XCTAssertEqual(removes, 0)
    }
    func testColdUnknownKeepsStoredLabelAndNeverReplaysOnLoad() async throws {
        for (a, b) in pairs {
            for label in [a, b] {
                let f = try Fixture(), original = try mutation(label); try await f.journal.save(original)
                let model = f.model(); await model.load(); unknown(model)
                XCTAssertEqual(f.service.writes.count, 0)
                await model.retryExact(); XCTAssertEqual(f.service.writes.count, 1)
                labelBytes(f.service.writes.first?.label, label)
                XCTAssertEqual(model.decision, .saved); XCTAssertTrue(model.canEdit)
            }
        }
    }
    func testDeleteAndNumericEquivalentCoordinatesRetainOriginalJournalSemantics() async throws {
        let f = try Fixture()
        let original = try mutation("Exact")
        let equivalent = try PrivateHomeMutation(requestId: original.requestId, expectedVersion: 3, label: "Exact",
            point: PrivateHomePoint.parse(latitude: "12.000000", longitude: "45.000000"))
        try await f.journal.save(original); let bytes = await f.vault.snapshot()
        try await f.journal.save(equivalent); let after = await f.vault.snapshot(); sameBytes(bytes, after)
        try await f.journal.clear(matching: equivalent)
        let delete = try PrivateHomeMutation(requestId: "delete-original", expectedVersion: 4)
        try await f.journal.save(delete); try await f.journal.save(delete); try await f.journal.clear(matching: delete)
        let empty = await f.vault.snapshot(); XCTAssertTrue(empty.isEmpty)
    }
}
