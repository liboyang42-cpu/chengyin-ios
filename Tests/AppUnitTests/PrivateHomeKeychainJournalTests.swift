import XCTest
import CryptoKit
@testable import Questify

/// Synthetic, actor-isolated persistence emulator. Never calls Security or writes any real location.
private actor PrivateHomeSyntheticVault: PrivateHomeKeychainPrimitive {
    var items: [String: PrivateHomeKeychainItem] = [:]
    var unavailable = false
    var replacementOnRemove: PrivateHomeKeychainItem?
    func setUnavailable(_ value: Bool) { unavailable = value }
    func snapshot() -> [String: PrivateHomeKeychainItem] { items }
    func restore(_ value: [String: PrivateHomeKeychainItem]) { items = value }
    func replaceDuringRemove(_ item: PrivateHomeKeychainItem) { replacementOnRemove = item }
    func read(key: String) throws -> PrivateHomeKeychainItem? {
        if unavailable { throw PrivateHomeIssue.storageUnavailable }; return items[key]
    }
    func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
        if unavailable { throw PrivateHomeIssue.storageUnavailable }
        guard items[key] == nil else { return false }; items[key] = item; return true
    }
    func remove(key: String, matchingTag: Data) throws -> Bool {
        if unavailable { throw PrivateHomeIssue.storageUnavailable }
        if let replacementOnRemove { items[key] = replacementOnRemove; self.replacementOnRemove = nil }
        guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
    }
}
@MainActor final class PrivateHomeKeychainJournalTests: XCTestCase {
    private func context(account: Int = 12, realm: String = "synthetic-a") throws -> (RegionalSessionStorageScope, PlayExperienceSession) {
        let endpoint = "https://private-home.example.test"
        let config = try RegionalConfiguration(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]])
        let scope = try RegionalSessionStorageScope(configuration: config, bundleIdentifier: "example.privateHome", realm: realm)
        return (scope, try PlayExperienceSession(accountID: account, epoch: 1, namespace: scope.service, token: "fixture-token"))
    }
    private func mutation(_ id: String = "synthetic-a", label: String = "Synthetic") throws -> PrivateHomeMutation {
        try PrivateHomeMutation(requestId: id, expectedVersion: 0, label: label, point: PrivateHomePoint.parse(latitude: "12.345", longitude: "45.678"))
    }
    private func journal(_ vault: PrivateHomeSyntheticVault, account: Int = 12, realm: String = "synthetic-a") throws -> PrivateHomeKeychainJournal {
        let (scope, owner) = try context(account: account, realm: realm)
        return try PrivateHomeKeychainJournal(storageScope: scope, owner: owner, primitive: vault)
    }
    func testExactDuplicateAllowedDifferentMutationCannotOverwrite() async throws {
        let vault = PrivateHomeSyntheticVault(), journal = try journal(vault), first = try mutation()
        try await journal.save(first); try await journal.save(first)
        do { try await journal.save(mutation("different-id")); XCTFail() } catch { }
        do { try await journal.save(mutation(label: "Changed payload")); XCTFail() } catch { }
        let stored = try await journal.read(); XCTAssertEqual(stored, first)
        let count = await vault.snapshot().count; XCTAssertEqual(count, 1)
    }
    func testMetadataTagIsRandomAndNotAPrivatePayloadDigest() async throws {
        let firstVault = PrivateHomeSyntheticVault(), secondVault = PrivateHomeSyntheticVault(), request = try mutation()
        try await journal(firstVault).save(request); try await journal(secondVault).save(request)
        let firstItems = await firstVault.snapshot(), secondItems = await secondVault.snapshot()
        let a = try XCTUnwrap(firstItems.values.first), b = try XCTUnwrap(secondItems.values.first)
        XCTAssertEqual(a.tag.count, 32); XCTAssertNotEqual(a.tag, b.tag)
        XCTAssertNotEqual(a.tag, Data(SHA256.hash(data: a.bytes)))
        let decoded = try JSONSerialization.jsonObject(with: a.bytes) as? [String: Any]
        XCTAssertNotNil(decoded?["payloadFingerprint"])
    }
    func testConcurrentWritersHaveOnlyOneWinner() async throws {
        let vault = PrivateHomeSyntheticVault(), a = try journal(vault), b = try journal(vault)
        let first = try mutation("first"), second = try mutation("second")
        let one = Task { () -> Bool in do { try await a.save(first); return true } catch { return false } }
        let two = Task { () -> Bool in do { try await b.save(second); return true } catch { return false } }
        let outcomes = await [one.value, two.value]
        XCTAssertEqual(outcomes.filter { $0 }.count, 1)
        let stored = try await a.read(); XCTAssertTrue(stored == first || stored == second)
    }
    func testRecreatedVaultAndJournalRecoverPendingExactly() async throws {
        let vault = PrivateHomeSyntheticVault(), first = try mutation()
        try await journal(vault).save(first)
        let durableBytes = await vault.snapshot(), reopened = PrivateHomeSyntheticVault()
        await reopened.restore(durableBytes)
        let recovered = try await journal(reopened).read(); XCTAssertEqual(recovered, first)
        try await journal(reopened).clear(matching: first)
        let empty = try await journal(reopened).read(); XCTAssertNil(empty)
    }
    func testWrongRequestAndSameIDDifferentPayloadCannotClear() async throws {
        let vault = PrivateHomeSyntheticVault(), journal = try journal(vault), first = try mutation()
        try await journal.save(first)
        for wrong in [try mutation("wrong"), try mutation(label: "Wrong payload")] {
            do { try await journal.clear(matching: wrong); XCTFail() } catch { }
        }
        let stored = try await journal.read(); XCTAssertEqual(stored, first)
    }
    func testReplacementBetweenReadAndDeleteSurvivesConditionalDelete() async throws {
        let vault = PrivateHomeSyntheticVault(), journal = try journal(vault), first = try mutation()
        try await journal.save(first)
        let replacementVault = PrivateHomeSyntheticVault(), replacement = try mutation("new-request")
        try await self.journal(replacementVault).save(replacement)
        let replacementItems = await replacementVault.snapshot(), item = try XCTUnwrap(replacementItems.values.first)
        await vault.replaceDuringRemove(item)
        do { try await journal.clear(matching: first); XCTFail() } catch { }
        let stored = try await journal.read(); XCTAssertEqual(stored, replacement)
    }
    func testAccountAndRealmIsolatePendingRecordsAndRejectMismatchedScope() async throws {
        let vault = PrivateHomeSyntheticVault(), first = try mutation()
        try await journal(vault).save(first)
        let otherAccount = try await journal(vault, account: 13).read(), otherRealm = try await journal(vault, realm: "synthetic-b").read()
        XCTAssertNil(otherAccount); XCTAssertNil(otherRealm)
        let (scope, _) = try context(), (_, other) = try context(realm: "synthetic-b")
        XCTAssertThrowsError(try PrivateHomeKeychainJournal(storageScope: scope, owner: other, primitive: vault))
    }
    func testLockedAndCorruptStorageFailClosedWithoutErasingPending() async throws {
        let vault = PrivateHomeSyntheticVault(), journal = try journal(vault), first = try mutation()
        try await journal.save(first); await vault.setUnavailable(true)
        do { _ = try await journal.read(); XCTFail() } catch { }
        do { try await journal.clear(matching: first); XCTFail() } catch { }
        await vault.setUnavailable(false)
        let stored = try await journal.read(); XCTAssertEqual(stored, first)
        var snapshot = await vault.snapshot(); let key = try XCTUnwrap(snapshot.keys.first)
        snapshot[key] = PrivateHomeKeychainItem(bytes: Data("corrupt".utf8), tag: Data(repeating: 0, count: 32))
        await vault.restore(snapshot)
        do { _ = try await journal.read(); XCTFail() } catch { }
        do { try await journal.save(first); XCTFail() } catch { }
        let count = await vault.snapshot().count; XCTAssertEqual(count, 1)
    }
}
