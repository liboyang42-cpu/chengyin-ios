import XCTest
@testable import Questify

actor NativeHomeReturnSyntheticVault: PrivateHomeKeychainPrimitive {
    var items: [String: PrivateHomeKeychainItem] = [:]
    var locked = false
    var replacement: PrivateHomeKeychainItem?
    func snapshot() -> [String: PrivateHomeKeychainItem] { items }
    func lock() { locked = true }
    func replaceOnRemove(_ item: PrivateHomeKeychainItem) { replacement = item }
    func read(key: String) throws -> PrivateHomeKeychainItem? {
        guard !locked else { throw NativeHomeReturnFailure.storageUnavailable }; return items[key]
    }
    func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
        guard !locked else { throw NativeHomeReturnFailure.storageUnavailable }
        guard items[key] == nil else { return false }; items[key] = item; return true
    }
    func remove(key: String, matchingTag: Data) throws -> Bool {
        guard !locked else { throw NativeHomeReturnFailure.storageUnavailable }
        if let replacement { items[key] = replacement; self.replacement = nil }
        guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
    }
}

@MainActor final class NativeHomeReturnKeychainJournalTests: XCTestCase {
    func context(account: Int = 7, realm: String = "synthetic-a") throws -> (RegionalSessionStorageScope, PlayExperienceSession) {
        let endpoint = "https://home-return.example.test"
        let configuration = try RegionalConfiguration(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]])
        let scope = try RegionalSessionStorageScope(configuration: configuration, bundleIdentifier: "example.homeReturn", realm: realm)
        return (scope, try .init(accountID: account, epoch: 1, namespace: scope.service, token: "synthetic-token"))
    }
    func journal(_ vault: NativeHomeReturnSyntheticVault, account: Int = 7, realm: String = "synthetic-a") throws -> NativeHomeReturnKeychainJournal {
        let (scope, owner) = try context(account: account, realm: realm)
        return try .init(storageScope: scope, owner: owner, primitive: vault)
    }
    func request(_ id: String = "synthetic-restore-1") throws -> NativeHomeRestoreRequest {
        try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: Data("{\"proofId\":\"proof-1\",\"requestId\":\"\(id)\",\"homeVersion\":3,\"expectedAccountVersion\":4,\"scopeType\":\"RUN\",\"scopeId\":\"42\",\"resourceType\":\"sys.hp\"}".utf8))
    }
    func testRestartRetainsExactUnknownAndNoCoordinatesInRecord() async throws {
        let vault = NativeHomeReturnSyntheticVault(), first = try journal(vault), original = try request()
        try await first.save(original)
        let reopened = try journal(vault), restored = try await reopened.read()
        XCTAssertEqual(restored, original)
        let snapshot = await vault.snapshot(), item = try XCTUnwrap(snapshot.values.first)
        let text = try XCTUnwrap(String(data: item.bytes, encoding: .utf8))
        for field in ["latitude", "longitude", "accuracyMeters", "capturedAtMillis", "token"] { XCTAssertFalse(text.contains(field)) }
        XCTAssertTrue(snapshot.keys.allSatisfy { $0.hasPrefix("home-return.v1:") })
    }
    func testAtomicInsertOnlyAndDifferentOwnersRealmsCannotReadUnknown() async throws {
        let vault = NativeHomeReturnSyntheticVault(), first = try journal(vault), original = try request()
        try await first.save(original); try await first.save(original)
        do { try await first.save(request("different-request")); XCTFail() } catch {}
        let otherAccount = try await journal(vault, account: 8).read(), otherRealm = try await journal(vault, realm: "synthetic-b").read()
        XCTAssertNil(otherAccount); XCTAssertNil(otherRealm)
        let stored = try await first.read(); XCTAssertEqual(stored, original)
    }
    func testConditionalClearDoesNotEraseReplacementGeneration() async throws {
        let vault = NativeHomeReturnSyntheticVault(), first = try journal(vault), original = try request()
        try await first.save(original)
        let otherVault = NativeHomeReturnSyntheticVault(), other = try journal(otherVault)
        try await other.save(original)
        let snapshots = await otherVault.snapshot(), replacement = try XCTUnwrap(snapshots.values.first)
        await vault.replaceOnRemove(replacement)
        do { try await first.clear(matching: original); XCTFail() } catch {}
        let stillStored = try await first.read(); XCTAssertEqual(stillStored, original)
    }
    func testLockedJournalNeverMasqueradesAsEmptyAndHomeJournalKeyIsSeparate() async throws {
        let vault = NativeHomeReturnSyntheticVault(), first = try journal(vault)
        let (scope, owner) = try context()
        let home = try PrivateHomeKeychainJournal(storageScope: scope, owner: owner, primitive: vault)
        try await first.save(request()); let privateHomePending = try await home.read(); XCTAssertNil(privateHomePending)
        await vault.lock()
        do { _ = try await first.read(); XCTFail() } catch {}
    }
}
