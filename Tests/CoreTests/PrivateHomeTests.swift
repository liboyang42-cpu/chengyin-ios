import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PrivateHomeTests: XCTestCase {
    private func owner(_ account: Int = 12, epoch: UInt64 = 1, namespace: String = "realm-a") throws -> PlayExperienceSession {
        try PlayExperienceSession(accountID: account, epoch: epoch, namespace: namespace, token: "fixture-token")
    }
    private func point() throws -> PrivateHomePoint { try PrivateHomePoint.parse(latitude: "12.345", longitude: "45.678") }
    private func snapshot(_ version: Int64 = 0) throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":\(version),\"status\":\"DELETED\"}".utf8))
    }
    private final class Journal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var failSave = false, failClear = false, failRead = false
        init(_ owner: PlayExperienceSession) { scope = PrivateHomeJournalScope(owner: owner) }
        func read() throws -> PrivateHomeMutation? { if failRead { throw PrivateHomeIssue.storageUnavailable }; return value }
        func save(_ mutation: PrivateHomeMutation) throws { if failSave { throw PrivateHomeIssue.storageUnavailable }; guard value == nil else { throw PrivateHomeIssue.busy }; value = mutation }
        func clear(matching mutation: PrivateHomeMutation) throws { if failClear { throw PrivateHomeIssue.storageUnavailable }; guard value == mutation else { throw PrivateHomeIssue.invalid }; value = nil }
    }
    private final class Service: PrivateHomeServing {
        var home: PrivateHomeSnapshot
        var mutations: [PrivateHomeMutation] = []
        var outcome: PrivateHomeReceipt.Decision = .saved
        var lose = false, mismatch = false
        var afterSend: (() -> Void)?
        init(_ home: PrivateHomeSnapshot) { self.home = home }
        func load() async throws -> PrivateHomeSnapshot { home }
        func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt {
            mutations.append(mutation); afterSend?()
            if lose { lose = false; throw PrivateHomeIssue.unknownOutcome }
            let version = mutation.expectedVersion + 1
            let json = "{\"requestId\":\"\(mismatch ? "wrong-id" : mutation.requestId)\",\"decision\":\"\(outcome.rawValue)\",\"version\":\(version)}"
            return try JSONDecoder().decode(PrivateHomeReceipt.self, from: Data(json.utf8))
        }
    }
    func testFullCoordinateInputCannotIgnoreTrailingCharacters() throws {
        for invalid in ["12junk", "1,234", " 12", "12 ", "1e2", "12.1234567", "NaN", "12\n"] {
            XCTAssertThrowsError(try PrivateHomePoint.parse(latitude: invalid, longitude: "45"), invalid)
        }
        XCTAssertEqual(try PrivateHomePoint.parse(latitude: "-12.345", longitude: "+45.678").latitude, Decimal(string: "-12.345"))
    }
    func testDeleteDoubleConfirmationDispatchesOnlyOnceAndFailedReadBlocks() async throws {
        let o = try owner(), service = try Service(snapshot()), journal = Journal(o)
        service.home = try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":1,\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}".utf8))
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        journal.failRead = true; await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit)
        journal.failRead = false; await model.load(); model.prepareDelete(); service.outcome = .deleted
        await model.confirm(); await model.confirm(); XCTAssertEqual(service.mutations.count, 1)
        XCTAssertEqual(service.mutations.first?.method, "DELETE"); XCTAssertNil(service.mutations.first?.latitude)
    }
    func testMaximumReturnedVersionSettlesButCannotBeMutatedAgain() throws {
        let mutation = try PrivateHomeMutation(requestId: "max-version", expectedVersion: Int64.max - 1)
        let receipt = try JSONDecoder().decode(PrivateHomeReceipt.self, from: Data("{\"requestId\":\"max-version\",\"version\":9223372036854775807,\"decision\":\"DELETED\"}".utf8))
        try receipt.validate(for: mutation)
        let home = try snapshot(Int64.max); try home.validate()
        XCTAssertThrowsError(try PrivateHomeMutation(expectedVersion: home.version))
    }
    func testMutationBodyHasNoOwnerAndDeleteOmitsCoordinates() throws {
        let mutation = try PrivateHomeMutation(expectedVersion: 2)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(mutation)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["requestId", "expectedVersion"])
        XCTAssertEqual(mutation.method, "DELETE")
        let set = try PrivateHomeMutation(expectedVersion: 2, label: "Synthetic", point: point())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["requestId", "expectedVersion", "label", "latitude", "longitude", "datum"])
        XCTAssertEqual(String(describing: set), "PrivateHome[redacted]")
        XCTAssertEqual(String(reflecting: try point()), "PrivateHome[redacted]")
    }
    func testRejectsInvalidPrecisionLabelsAndVersions() throws {
        XCTAssertThrowsError(try PrivateHomePoint(latitude: Decimal(string: "1.1234567")!, longitude: 0))
        XCTAssertThrowsError(try PrivateHomePoint(latitude: 91, longitude: 0))
        XCTAssertThrowsError(try PrivateHomeMutation(expectedVersion: -1))
        XCTAssertThrowsError(try PrivateHomeMutation(requestId: "x/y", expectedVersion: 0))
        XCTAssertThrowsError(try PrivateHomeMutation(requestId: "valid-id\n", expectedVersion: 0))
        XCTAssertThrowsError(try PrivateHomeMutation(expectedVersion: 0, label: "😀", point: point()))
        XCTAssertThrowsError(try PrivateHomeMutation(expectedVersion: 0, label: "a\nb", point: point()))
    }
    func testMissingSecureJournalAndDefaultOffCannotWrite() async throws {
        let o = try owner(), service = try Service(snapshot())
        let disabled = PrivateHomeCoordinator(service: service, owner: o, current: { o })
        await disabled.load(); XCTAssertEqual(disabled.phase, .disabled)
        let noStore = PrivateHomeCoordinator(service: service, owner: o, enabled: true, current: { o })
        await noStore.load(); XCTAssertFalse(noStore.canEdit); noStore.prepareSet(label: "Synthetic", point: try point()); await noStore.confirm()
        XCTAssertTrue(service.mutations.isEmpty)
    }
    func testReviewCancelAndSaveFailureNeverDispatch() async throws {
        let o = try owner(), service = try Service(snapshot()), journal = Journal(o)
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        await model.load(); model.prepareSet(label: "Synthetic", point: try point()); model.cancelReview(); await model.confirm()
        XCTAssertTrue(service.mutations.isEmpty); XCTAssertNil(journal.value)
        model.prepareSet(label: "Synthetic", point: try point()); journal.failSave = true; await model.confirm()
        XCTAssertEqual(model.phase, .blocked); XCTAssertTrue(service.mutations.isEmpty)
    }
    func testUnknownSurvivesCoordinatorRecreationAndGetDoesNotUnlock() async throws {
        let o = try owner(), service = try Service(snapshot()), journal = Journal(o)
        service.lose = true
        let first = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        await first.load(); first.prepareSet(label: "Synthetic", point: try point()); await first.confirm()
        let saved = try XCTUnwrap(journal.value); XCTAssertEqual(first.phase, .unknown)
        first.invalidate(); XCTAssertNotNil(journal.value); XCTAssertNil(first.home)
        let restarted = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        await restarted.load(); XCTAssertTrue(restarted.canRetry); XCTAssertFalse(restarted.canEdit)
        await restarted.load(); XCTAssertEqual(journal.value, saved)
        await restarted.retryExact(); XCTAssertEqual(service.mutations, [saved, saved]); XCTAssertNil(journal.value)
    }
    func testMismatchedReceiptAndJournalClearFailureKeepUnknownLock() async throws {
        let o = try owner(), service = try Service(snapshot()), journal = Journal(o)
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        service.mismatch = true; await model.load(); model.prepareSet(label: "Synthetic", point: try point()); await model.confirm()
        XCTAssertTrue(model.canRetry); XCTAssertNotNil(journal.value)
        service.mismatch = false; journal.failClear = true; await model.retryExact()
        XCTAssertTrue(model.canRetry); XCTAssertNotNil(journal.value); XCTAssertFalse(model.canEdit)
    }
    func testConflictRefreshRequiresNewExplicitReviewAndRequestID() async throws {
        let o = try owner(), service = try Service(snapshot()), journal = Journal(o)
        service.outcome = .conflict
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        await model.load(); model.prepareSet(label: "Synthetic", point: try point()); let old = try XCTUnwrap(model.review)
        service.home = try snapshot(1); await model.confirm()
        XCTAssertEqual(model.decision, .conflict); XCTAssertNil(model.review); XCTAssertEqual(service.mutations.count, 1)
        model.prepareSet(label: "Reviewed again", point: try point())
        XCTAssertEqual(model.review?.expectedVersion, 1); XCTAssertNotEqual(model.review?.requestId, old.requestId)
    }
    func testScopeMismatchNeverReadsOtherAccountJournal() async throws {
        let o = try owner(), other = try owner(99), service = try Service(snapshot()), journal = Journal(other)
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { o })
        await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertNil(model.home)
    }
    func testLogoutDuringMutationDropsResultButKeepsDurableLock() async throws {
        let o = try owner(), service = try Service(snapshot()), journal = Journal(o)
        var current: PlayExperienceSession? = o
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: o, enabled: true, current: { current })
        await model.load(); model.prepareSet(label: "Synthetic", point: try point())
        service.afterSend = { current = nil }; await model.confirm()
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.home); XCTAssertNotNil(journal.value)
    }
}

@MainActor final class PrivateHomeTransportTests: XCTestCase {
    final class RecordingTransport: HTTPTransport {
        var requests: [URLRequest] = []
        var json = "{\"code\":200,\"data\":{\"version\":0,\"status\":\"DELETED\"}}"
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), 200) }
    }
    func testExactOwnerRouteAndPrivacyHeaders() async throws {
        let transport = RecordingTransport()
        let owner = try PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture", token: "fixture-token")
        let service = PrivateHomeService(api: try APIConfiguration(baseURL: URL(string: "https://private-home.example.test")!), transport: transport, owner: owner, enabled: true, current: { owner })
        _ = try await service.load()
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/native/home"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let delete = try PrivateHomeMutation(requestId: "synthetic-delete", expectedVersion: 0)
        transport.json = "{\"code\":200,\"data\":{\"requestId\":\"synthetic-delete\",\"version\":1,\"decision\":\"DELETED\"}}"
        _ = try await service.mutate(delete)
        XCTAssertEqual(transport.requests.last?.httpMethod, "DELETE")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(transport.requests.last?.httpBody, try encoder.encode(delete))
    }
    func testDisabledAndChangedRealmNeverDispatch() async throws {
        let transport = RecordingTransport(), api = try APIConfiguration(baseURL: URL(string: "https://private-home.example.test")!)
        let owner = try PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture", token: "fixture-token")
        let changed = try PlayExperienceSession(accountID: 12, epoch: 2, namespace: "other", token: "fixture-token")
        for service in [PrivateHomeService(api: api, transport: transport, owner: owner, current: { owner }), PrivateHomeService(api: api, transport: transport, owner: owner, enabled: true, current: { changed })] {
            do { _ = try await service.load(); XCTFail("Must reject") } catch { }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
