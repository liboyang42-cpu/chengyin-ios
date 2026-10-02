import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ImageJournalTestStorage {
    var values: [String: Data] = [:]
    var failRead = false
    var failWrite = false
    var discardWrite = false
    func journal() -> StoredImageUploadJournal {
        StoredImageUploadJournal(read: { key in
            if self.failRead { throw ImageUploadJournalFailure.unavailable }; return self.values[key]
        }, write: { data, key in
            if self.failWrite { throw ImageUploadJournalFailure.unavailable }
            if !self.discardWrite { self.values[key] = data }
        })
    }
}
private final class JournalUploadTransport: HTTPTransport {
    var count = 0
    var failAfterSend = false
    var beforeReturn: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        count += 1; beforeReturn?()
        if failAfterSend { throw URLError(.networkConnectionLost) }
        return (Data(#"{"code":200,"url":"https://media.example.com/a.jpg"}"#.utf8), 200)
    }
}
@MainActor final class ImageUploadJournalTests: XCTestCase {
    func scope(account: Int = 8, epoch: UUID = UUID(), resource: Int? = nil, namespace: String = "deployment-one") throws -> RetainedImageScope {
        try .init(accountID: account, epoch: epoch, realm: "https://api.example.com", destination: .merchant(merchantRowID: 73, field: .imgUrl), accessRevision: UUID(), resourceID: resource, namespace: namespace)
    }
    func owner(_ scope: RetainedImageScope, _ storage: ImageJournalTestStorage, _ transport: JournalUploadTransport) throws -> RetainedImageUploadCoordinator {
        let uploader = try RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: scope.realm)!), transport: transport,
            enabled: true, approvedOrigins: ["https://media.example.com"], currentScope: { scope }, token: { "fixture-token" })
        return RetainedImageUploadCoordinator(uploader: uploader, journal: storage.journal())
    }
    func upload(_ owner: RetainedImageUploadCoordinator, scope: RetainedImageScope) async throws {
        owner.prepare(try .init(jpeg: Data([255,216,255]), width: 1, height: 1), scope: scope)
        guard case .reviewing(let review) = owner.state else { return XCTFail("Expected review") }
        await owner.confirm(review)
    }
    func testPartialSendRecreatedOwnerNewEpochNewDraftRemainsLocked() async throws {
        let storage = ImageJournalTestStorage(), transport = JournalUploadTransport(), first = try scope()
        transport.failAfterSend = true
        let a = try owner(first, storage, transport)
        try await upload(a, scope: first)
        XCTAssertEqual(a.state, .unknown)
        let second = try scope() // New epoch/access/screen identity; same nil-template target.
        let b = try owner(second, storage, transport)
        b.prepare(try .init(jpeg: Data([255,216,255]), width: 1, height: 1), scope: second)
        XCTAssertEqual(b.state, .unknown); XCTAssertEqual(transport.count, 1)
    }
    func testWriteAheadExistsBeforeTransportAndAcknowledgementIsNotDraftApplication() async throws {
        let storage = ImageJournalTestStorage(), transport = JournalUploadTransport(), s = try scope()
        let target = try ImageUploadTarget(scope: s)
        transport.beforeReturn = { XCTAssertEqual(try? storage.journal().entry(for: target)?.phase, .pending) }
        let a = try owner(s, storage, transport); try await upload(a, scope: s)
        guard case .uploaded = a.state else { return XCTFail() }
        XCTAssertEqual(try storage.journal().entry(for: target)?.phase, .acknowledged)
        // No local application was invoked. Recreating must not reconstruct a proof from metadata.
        let recreated = try owner(scope(), storage, transport)
        XCTAssertEqual(recreated.state, .unknown)
        let raw = String(decoding: try XCTUnwrap(storage.values.values.first), as: UTF8.self)
        for secret in ["fixture-token", "media.example.com", "jpeg", "selection", "accessRevision", "epoch"] { XCTAssertFalse(raw.contains(secret)) }
    }
    func testVerifiedLocalConsumptionAllowsOnlyFreshReviewWithoutPublishingReceipt() async throws {
        let storage = ImageJournalTestStorage(), transport = JournalUploadTransport(), s = try scope()
        let a = try owner(s, storage, transport); try await upload(a, scope: s)
        guard case .uploaded(let proof) = a.state else { return XCTFail() }
        XCTAssertFalse(a.applyLocally(proof, consume: { _ in false }))
        XCTAssertEqual(try storage.journal().entry(for: ImageUploadTarget(scope: s))?.phase, .acknowledged)
        XCTAssertTrue(a.applyLocally(proof, consume: { image in
            var draft = MerchantNodeTemplate(); draft.id = s.resourceID
            guard let result = try? image.applying(to: .template(draft), expectedScope: s),
                  case .template(let updated) = result else { return false }
            return updated.imgURL == image.url.absoluteString
        }))
        XCTAssertEqual(try storage.journal().entry(for: ImageUploadTarget(scope: s))?.phase, .locallyApplied)
        XCTAssertEqual(transport.count, 1)
        let recreated = try owner(scope(), storage, transport)
        XCTAssertEqual(recreated.state, .idle); XCTAssertEqual(transport.count, 1)
        // Another explicit selection and confirmation is required, never an automatic retry.
        try await upload(a, scope: s); XCTAssertEqual(transport.count, 2)
    }
    func testLocalApplicationWriteFailureDoesNotUnlock() async throws {
        let storage = ImageJournalTestStorage(), transport = JournalUploadTransport(), s = try scope()
        let a = try owner(s, storage, transport); try await upload(a, scope: s)
        guard case .uploaded(let proof) = a.state else { return XCTFail() }
        storage.failWrite = true
        XCTAssertFalse(a.applyLocally(proof, consume: { _ in true })); XCTAssertEqual(a.state, .unknown)
        storage.failWrite = false
        XCTAssertEqual(try owner(scope(), storage, transport).state, .unknown)
    }
    func testCorruptionReadErrorAndFailedWriteNeverDispatch() async throws {
        for failure in 0..<4 {
            let storage = ImageJournalTestStorage(), transport = JournalUploadTransport(), s = try scope()
            if failure == 0 {
                try storage.journal().begin(target: ImageUploadTarget(scope: s), attemptID: UUID())
                for key in storage.values.keys { storage.values[key] = Data("broken".utf8) }
            }
            if failure == 1 { storage.failRead = true }
            let a = try owner(s, storage, transport)
            if failure == 2 { storage.failWrite = true }
            if failure == 3 { storage.discardWrite = true }
            a.prepare(try .init(jpeg: Data([255,216,255]), width: 1, height: 1), scope: s)
            if case .reviewing(let review) = a.state { await a.confirm(review) }
            XCTAssertEqual(a.state, .unknown); XCTAssertEqual(transport.count, 0)
        }
    }
    func testAcknowledgementPersistenceFailureRetainsUnknown() async throws {
        let storage = ImageJournalTestStorage(), transport = JournalUploadTransport(), s = try scope()
        transport.beforeReturn = { storage.failWrite = true }
        let a = try owner(s, storage, transport); try await upload(a, scope: s)
        XCTAssertEqual(a.state, .unknown)
        storage.failWrite = false
        XCTAssertEqual(try storage.journal().entry(for: ImageUploadTarget(scope: s))?.phase, .pending)
        XCTAssertEqual(try owner(scope(), storage, transport).state, .unknown)
    }
    func testAccountNamespaceAndSavedTemplateRemainIndependent() throws {
        let storage = ImageJournalTestStorage(), s = try scope()
        try storage.journal().begin(target: ImageUploadTarget(scope: s), attemptID: UUID())
        for other in [try scope(account: 9), try scope(resource: 4), try scope(namespace: "deployment-two")] {
            XCTAssertNil(try storage.journal().entry(for: ImageUploadTarget(scope: other)))
        }
    }
    func testWrongAttemptAndCorruptVersionCannotUnlock() throws {
        let storage = ImageJournalTestStorage(), target = try ImageUploadTarget(scope: scope())
        try storage.journal().begin(target: target, attemptID: UUID())
        XCTAssertThrowsError(try storage.journal().record(target: target, attemptID: UUID(), phase: .rejected))
        for key in storage.values.keys {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: storage.values[key]!) as? [String: Any])
            json["version"] = 99; storage.values[key] = try JSONSerialization.data(withJSONObject: json)
        }
        XCTAssertThrowsError(try storage.journal().entry(for: target))
    }
}
