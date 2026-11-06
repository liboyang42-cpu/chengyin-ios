import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class OperationPendingListingCompatibilityTests: XCTestCase {
    func testLegacyPendingRecordWithoutWebhookMetadataStillDecodes() throws {
        let id = UUID()
        let raw = try JSONSerialization.data(withJSONObject: ["operationID": id.uuidString,
            "ownerKey": "owner", "targetKey": "target", "acknowledgedSteps": 2])
        let record = try JSONDecoder().decode(OperationPendingRecord.self, from: raw)
        XCTAssertEqual(record.operationID, id)
        XCTAssertEqual(record.acknowledgedSteps, 2)
        XCTAssertNil(record.nativeWebhook)
    }
    func testOrdinaryEncodingDoesNotAddWebhookOrCredentialFields() throws {
        let value = OperationPendingRecord(ownerKey: "owner", targetKey: "target")
        let raw = try JSONEncoder().encode(value)
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(Set(dictionary.keys), ["operationID", "ownerKey", "targetKey", "acknowledgedSteps"])
        XCTAssertEqual(try JSONDecoder().decode(OperationPendingRecord.self, from: raw), value)
    }
    func testListingReturnsOnlyExactOwnerIncludingLengthPrefixAndColon() throws {
        try withJournal { journal, _ in
            let selected = [OperationPendingRecord(ownerKey: "1:a:b", targetKey: "one"),
                            OperationPendingRecord(ownerKey: "1:a:b", targetKey: "two:extra")]
            for row in selected + [OperationPendingRecord(ownerKey: "1:a", targetKey: "b:one"),
                                   OperationPendingRecord(ownerKey: "1:a:bc", targetKey: "two")] { try journal.write(row) }
            let result = try journal.pendingRecords(ownerKey: "1:a:b")
            XCTAssertEqual(Set(result.map(\.operationID)), Set(selected.map(\.operationID)))
            XCTAssertEqual(result.count, 2)
        }
    }
    func testCorruptOtherOwnerDoesNotBlockThisOwnersRecovery() throws {
        try withJournal { journal, defaults in
            let selected = OperationPendingRecord(ownerKey: "owner", targetKey: "one")
            try journal.write(selected)
            defaults.set(Data("invalid".utf8), forKey: storageKey("other", "one"))
            defaults.set(Data("invalid".utf8), forKey: "questify.operations.pending.v1.not-base64")
            XCTAssertEqual(try journal.pendingRecords(ownerKey: "owner"), [selected])
        }
    }
    func testCorruptSelectedOwnerCannotBeSilentlySkippedOrRebound() throws {
        try withJournal { journal, defaults in
            let wrong = OperationPendingRecord(ownerKey: "other", targetKey: "one")
            defaults.set(try JSONEncoder().encode(wrong), forKey: storageKey("owner", "one"))
            XCTAssertThrowsError(try journal.pendingRecords(ownerKey: "owner"))
            XCTAssertNotNil(defaults.object(forKey: storageKey("owner", "one")))
        }
    }
    func testListingIsReadOnlyAndKeepsOriginalOperationIdentity() throws {
        try withJournal { journal, defaults in
            let record = OperationPendingRecord(ownerKey: "owner", targetKey: "target", acknowledgedSteps: 3)
            try journal.write(record)
            let before = defaults.data(forKey: storageKey("owner", "target"))
            XCTAssertEqual(try journal.pendingRecords(ownerKey: "owner"), [record])
            XCTAssertEqual(defaults.data(forKey: storageKey("owner", "target")), before)
            let next = OperationPendingRecord(ownerKey: "owner", targetKey: "target")
            try journal.replace(record, with: next)
            XCTAssertEqual(try journal.pendingRecords(ownerKey: "owner"), [next])
        }
    }
    private func storageKey(_ owner: String, _ target: String) -> String {
        "questify.operations.pending.v1." + Data("\(owner.utf8.count):\(owner):\(target)".utf8).base64EncodedString()
    }
    private func withJournal(_ work: (OperationDefaultsJournal, UserDefaults) throws -> Void) throws {
        let suite = "OperationPendingListingCompatibilityTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try work(OperationDefaultsJournal(defaults: defaults), defaults)
    }
}
