import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import XCTest
@testable import QuestifyCore

/// Source only. These single-process cases are NOT the required dual-process/crash proof.
@MainActor final class MerchantOfferWithdrawalUnifiedStoreTests: XCTestCase {
    private func fixture() throws -> (URL, MerchantOfferWithdrawalUnifiedStore) {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("offer-withdraw-locks-v1.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (url, MerchantOfferWithdrawalUnifiedStore(url: url))
    }
    private func pending(_ id: UUID = UUID(), offer: Int = 3, realm: String = "https://example.invalid/") throws -> MerchantOfferWithdrawalOriginalPending {
        try .init(accountID: 1, merchantID: 2, offerID: offer, namespace: "fixture", realm: realm,
                  requestID: id, intentSHA256: String(repeating: "a", count: 64),
                  reasonSHA256: String(repeating: "b", count: 64), expectedSHA256: String(repeating: "c", count: 64))
    }
    private func key(_ realm: String = "https://example.invalid/", offer: Int = 3) -> String {
        "endpoint:" + Data(realm.utf8).base64EncodedString() + ":1:offer-\(offer)"
    }
    func testUnscopedLegacyUnknownBlocksOriginalWithoutChangingBytes() throws {
        let (url, store) = try fixture(); let bytes = try JSONEncoder().encode(["1:offer-3"])
        try bytes.write(to: url)
        XCTAssertThrowsError(try store.begin(pending()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testAtomicAcquireChecksLegacyAliasNotOnlyScopedKey() throws {
        let (_, store) = try fixture(); try store.acquire("1:offer-3")
        XCTAssertThrowsError(try store.acquire(key()))
    }
    func testOriginalSurvivesNewInstanceAndBlocksLegacyCompletion() throws {
        let (url, store) = try fixture(); let p = try pending(); try store.begin(p)
        let next = MerchantOfferWithdrawalUnifiedStore(url: url)
        XCTAssertEqual(try next.pending(account: 1, merchant: 2, offer: 3, namespace: "fixture", realm: p.realm), p)
        XCTAssertThrowsError(try next.acquire(key()))
        XCTAssertThrowsError(try next.complete(key()))
        XCTAssertThrowsError(try next.acknowledge(pending()))
        try next.acknowledge(p)
        XCTAssertFalse(try next.contains(key()))
    }
    func testSeparateInstancesRetainUnrelatedLegacyKeys() throws {
        let (url, store) = try fixture(); let other = MerchantOfferWithdrawalUnifiedStore(url: url)
        try store.acquire(key(offer: 3)); try other.acquire(key(offer: 4))
        XCTAssertTrue(try store.contains(key(offer: 3)))
        XCTAssertTrue(try store.contains(key(offer: 4)))
    }
    func testCorruptionAndMissingOriginalResourceFailClosed() throws {
        let (url, store) = try fixture(); try Data("not-json".utf8).write(to: url)
        XCTAssertThrowsError(try store.acquire(key()))
        try JSONEncoder().encode([String]()).write(to: url)
        try store.begin(pending())
        var rows = try JSONDecoder().decode([String].self, from: Data(contentsOf: url)); rows.removeAll { $0 == key() }
        try JSONEncoder().encode(rows).write(to: url)
        XCTAssertThrowsError(try store.contains(key()))
    }
    func testDefaultCompatibilityGateBlocksNewUUIDEvenIfFileIsEmpty() throws {
        let (_, store) = try fixture(); let journal = MerchantOfferWithdrawalOriginalJournal(store: store)
        XCTAssertFalse(journal.canBegin)
        XCTAssertThrowsError(try journal.begin(pending()))
        XCTAssertFalse(try store.contains(key()))
    }
    func testLegacyUnknownCannotBecomeAbsentOriginalRequest() throws {
        let (_, store) = try fixture(); try store.acquire(key())
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store)
        XCTAssertThrowsError(try journal.read(account: 1, merchant: 2, offer: 3, namespace: "fixture", realm: "https://example.invalid/"))
    }
    func testSameActorOfferOtherRealmDoesNotAcknowledgeOriginal() throws {
        let (_, store) = try fixture(); let p = try pending(); try store.begin(p)
        let other = try pending(offer: 3, realm: "https://other.invalid/")
        XCTAssertThrowsError(try store.acknowledge(other))
        XCTAssertEqual(try store.pending(account: 1, merchant: 2, offer: 3, namespace: "fixture", realm: p.realm), p)
    }
}


extension MerchantOfferWithdrawalUnifiedStoreTests {
    private func historicalFile(_ p: MerchantOfferWithdrawalOriginalPending, root: URL) throws -> URL {
        let identity = [String(p.accountID), String(p.merchantID), String(p.offerID), p.namespace, p.realm]
            .map { "\($0.utf8.count):\($0)" }.joined()
        let filename = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        let file = root.appendingPathComponent(filename)
        try JSONEncoder().encode(p).write(to: file)
        return file
    }
    func testKnownHistoricalRootReadsExactScopeAndNeverAcknowledgesOrRewrites() throws {
        let (url, store) = try fixture()
        let root = url.deletingLastPathComponent().appendingPathComponent("original-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let p = try pending(), file = try historicalFile(p, root: root), bytes = try Data(contentsOf: file)
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: [root])
        XCTAssertEqual(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm), [p])
        XCTAssertEqual(try journal.read(account: 1, merchant: 2, offer: 3, namespace: "fixture", realm: p.realm), p)
        XCTAssertTrue(try journal.entries(account: 9, merchant: 2, namespace: "fixture", realm: p.realm).isEmpty)
        XCTAssertTrue(try journal.entries(account: 1, merchant: 2, namespace: "other", realm: p.realm).isEmpty)
        XCTAssertThrowsError(try journal.read(account: 1, merchant: 2, offer: 3, namespace: "other", realm: p.realm))
        XCTAssertFalse(try journal.canAcknowledge(p))
        XCTAssertThrowsError(try journal.acknowledge(p))
        XCTAssertThrowsError(try journal.begin(p))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testConfiguredMissingHistoricalRootIsNotEmptyAndIsNeverCreated() throws {
        let (url, store) = try fixture(), root = url.deletingLastPathComponent().appendingPathComponent("absent")
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: [root])
        XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: "https://example.invalid/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testHistoricalSymlinkRootAncestorAndRecordAreRejected() throws {
        let (url, store) = try fixture(), directory = url.deletingLastPathComponent()
        let root = directory.appendingPathComponent("original-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let p = try pending(), file = try historicalFile(p, root: root)
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        for input in [alias, alias.appendingPathComponent("nested")] {
            let journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: [input])
            XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm))
        }
        let saved = directory.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: file, to: saved)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: saved)
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: [root])
        XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm))
        XCTAssertEqual(try JSONDecoder().decode(MerchantOfferWithdrawalOriginalPending.self, from: Data(contentsOf: saved)), p)
    }
    func testHistoricalWrongFilenameAndCurrentDuplicateFailClosed() throws {
        let (url, store) = try fixture(), root = url.deletingLastPathComponent().appendingPathComponent("original-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let p = try pending(), file = try historicalFile(p, root: root)
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: [root])
        try store.begin(p)
        XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm))
        XCTAssertThrowsError(try journal.read(account: 1, merchant: 2, offer: 3, namespace: "fixture", realm: p.realm))
        try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("wrong.json"))
        XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm))
        XCTAssertEqual(try store.pending(account: 1, merchant: 2, offer: 3, namespace: "fixture", realm: p.realm), p)
    }
    func testLegacyLockAndSidecarSymlinkAreRejectedWithoutChangingTargets() throws {
        let (url, store) = try fixture(), target = url.deletingLastPathComponent().appendingPathComponent("target")
        let bytes = Data("[]".utf8); try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        XCTAssertThrowsError(try store.begin(pending()))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        try FileManager.default.removeItem(at: url)
        let sidecar = url.appendingPathExtension("lock")
        try FileManager.default.removeItem(at: sidecar)
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: target)
        XCTAssertThrowsError(try store.begin(pending()))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }
}


extension MerchantOfferWithdrawalUnifiedStoreTests {
    func testUnreadableHistoricalRootAndRecordFailClosed() throws {
        guard geteuid() != 0 else { throw XCTSkip("Root bypasses POSIX permission checks") }
        let (url, store) = try fixture(), root = url.deletingLastPathComponent().appendingPathComponent("original-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let p = try pending(), file = try historicalFile(p, root: root)
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: [root])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        XCTAssertThrowsError(try journal.entries(account: 1, merchant: 2, namespace: "fixture", realm: p.realm))
    }
}
