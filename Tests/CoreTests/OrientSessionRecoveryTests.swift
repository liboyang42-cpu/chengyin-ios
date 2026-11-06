import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class OrientSessionRecoveryTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orient-tests-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("pending.json")
    }
    func testDurableRestartPreservesExactCommandAndNeverStoresCredentials() async throws {
        let url = try file()
        let original = try orientTestPending(.start(sessionID: 9, ackConfigVersion: 7))
        let store = try OrientSessionFileRecovery(fileURL: url)
        try store.prepare(original)
        let restarted = try OrientSessionFileRecovery(fileURL: url)
        XCTAssertEqual(try restarted.read(), original)
        let text = String(data: try Data(contentsOf: url), encoding: .utf8)!
        XCTAssertFalse(text.contains("synthetic-token")); XCTAssertFalse(text.contains("epoch")); XCTAssertFalse(text.contains("Authorization"))
        XCTAssertThrowsError(try restarted.prepare(orientTestPending(.abandon(sessionID: 9), key: "new-key-02")))
        XCTAssertEqual(try store.read(), original)
        try restarted.clear(matching: original); XCTAssertNil(try store.read())
    }
    func testClearComparesOwnerScopeKeyAndFullPayload() async throws {
        let store = try OrientSessionFileRecovery(fileURL: file())
        let original = try orientTestPending(.start(sessionID: 9, ackConfigVersion: 7))
        try store.prepare(original)
        let collisions = [
            try orientTestPending(.start(sessionID: 9, ackConfigVersion: 8)),
            try orientTestPending(.start(sessionID: 10, ackConfigVersion: 7)),
            try orientTestPending(.start(sessionID: 9, ackConfigVersion: 7), activity: 21),
            try OrientSessionPending(owner: orientTestOwner(account: 2), scope: orientTestScope(), key: original.key, operation: original.operation),
            try OrientSessionPending(owner: orientTestOwner(namespace: "synthetic-us-realm"), scope: orientTestScope(), key: original.key, operation: original.operation),
            try OrientSessionPending(owner: orientTestOwner(role: "merchant"), scope: orientTestScope(), key: original.key, operation: original.operation)
        ]
        for value in collisions {
            XCTAssertThrowsError(try store.clear(matching: value)); XCTAssertEqual(try store.read(), original)
        }
    }
    func testCorruptAndUnsupportedRecordsBlockWithoutOverwriting() async throws {
        let url = try file(); let store = try OrientSessionFileRecovery(fileURL: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("not-json".utf8); try corrupt.write(to: url)
        XCTAssertThrowsError(try store.read()); XCTAssertThrowsError(try store.prepare(orientTestPending(.prepare)))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        let original = try orientTestPending(.prepare)
        let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        var unsupported = data; unsupported["version"] = 2
        try JSONSerialization.data(withJSONObject: unsupported).write(to: url)
        XCTAssertThrowsError(try store.read())
        var malformed = data; malformed["key"] = "short"
        try JSONSerialization.data(withJSONObject: malformed).write(to: url)
        XCTAssertThrowsError(try store.read())
    }
    func testAlternativeEvidenceAndKeySurviveRestartForExactReplay() async throws {
        let url = try file(); let store = try OrientSessionFileRecovery(fileURL: url)
        let original = try orientTestPending(.alternative(sessionID: 9, taskID: 12, playInstanceID: "route:read", evidence: .quiz(answer: "原输入&+=中文")))
        try store.prepare(original)
        XCTAssertEqual(try OrientSessionFileRecovery(fileURL: url).read(), original)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testInvalidDecodedOwnerAndScopeAreRejected() async throws {
        let url = try file(); let store = try OrientSessionFileRecovery(fileURL: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try orientTestPending(.prepare)
        let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        var value = data; var owner = value["owner"] as! [String: Any]; owner["accountID"] = 0; value["owner"] = owner
        try JSONSerialization.data(withJSONObject: value).write(to: url)
        XCTAssertThrowsError(try store.read())
        value = data; value["scope"] = ["topicID": 3, "activityID": -1]
        try JSONSerialization.data(withJSONObject: value).write(to: url)
        XCTAssertThrowsError(try store.read())
    }
}
