import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ClubProfileDraftCurrentRecoveryTests: XCTestCase {
    private final class Memory: ClubProfileLocalDraftStorage {
        var rows: [String: ClubProfileLocalDraftBytes] = [:]
        func read(key: String) throws -> ClubProfileLocalDraftBytes? { rows[key] }
        func replace(key: String, expected: ClubProfileLocalDraftBytes?, data: Data?) throws -> ClubProfileLocalDraftBytes? {
            guard rows[key] == expected else { throw ClubProfileLocalDraftIssue.changed }
            let next = data.map { ClubProfileLocalDraftBytes(data: $0, tag: Data(repeating: 7, count: 32)) }
            rows[key] = next
            return next
        }
    }
    private func profile() throws -> ClubOperationsProfile {
        try JSONDecoder().decode(ClubOperationsProfile.self,
            from: Data(#"{"id":9,"name":"Example","city":"Example","isOwner":true}"#.utf8))
    }
    func testEqualReadCannotResolveAwaitingOriginalResult() throws {
        let storage = Memory(), profile = try profile()
        let store = ClubProfileLocalDraftStore(storage: storage)
        let scope = try ClubProfileLocalDraftScope(namespace: "test", accountID: 7, clubID: 9)
        let form = ClubProfileLocalDraftForm(ClubOperationsDraft(profile: profile))
        var record = ClubProfileLocalDraftRecord(scope: scope, profile: profile, form: form)
        record.attempt = .init(reviewID: UUID(), submitted: form, result: .awaitingOriginalResult)
        _ = try store.replace(record, scope: scope, expected: store.read(scope))
        let flow = ClubProfileLocalDraftFlow()
        let context = ClubProfileLocalDraftContext(store: store, namespace: "test",
            identity: .init(accountID: 7, epoch: 1), viewerRevision: 1, current: { true })
        _ = flow.begin(profile: profile, context: context)
        XCTAssertFalse(flow.reconcile(profile))
        XCTAssertNotNil(try store.read(scope).record?.attempt)
        flow.retire()
        XCTAssertNotNil(try store.read(scope).record?.attempt)
    }
    func testStoredReferencesRestoreWithoutMintingProof() throws {
        let profile = try profile()
        var draft = ClubOperationsDraft(profile: profile)
        draft.logo = "https://example.test/logo.jpg"
        let form = ClubProfileLocalDraftForm(draft)
        let restored = form.restoring(against: profile)
        XCTAssertNil(restored.logoUpload)
        XCTAssertNil(restored.coverUpload)
        XCTAssertThrowsError(try restored.validateMedia(original: profile))
        let a = try ClubProfileLocalDraftScope(namespace: "one", accountID: 7, clubID: 9)
        let b = try ClubProfileLocalDraftScope(namespace: "two", accountID: 7, clubID: 9)
        let c = try ClubProfileLocalDraftScope(namespace: "one", accountID: 8, clubID: 9)
        XCTAssertNotEqual(a.key, b.key)
        XCTAssertNotEqual(a.key, c.key)
    }
}
