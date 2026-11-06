import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ClubSeriesOriginalRequestJournalTests: XCTestCase {
    private func original(requestID: String = "original") throws -> ClubSeriesOriginalRequest {
        let command = try ClubGovernanceCommand(operation: .createSeries, scope: .init(clubID: 7, topicID: 8), values: [
            "requestId": .string(requestID), "recurrenceType": .string("WEEKLY"),
            "startDate": .string("2020-01-01"), "startTime": .string("09:00"), "occurrenceCount": .integer(4),
            "customDates": .null, "capacity": .null, "defaultLeadMemberId": .null,
            "waitlistEnabled": .bool(true), "offerMinutes": .integer(1440)])
        return try .init(realm: "fixture", accountID: 9, lockKey: "fixture|9|createSeries|clubId=7&topicId=8", command: command)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    func testRelaunchRetainsExactOriginalIncludingUnresolvedDefaultsAndPastDate() throws {
        let url = try directory(), value = try original()
        try ClubSeriesOriginalRequestFileStore(directory: url).reserve(value)
        let store = ClubSeriesOriginalRequestFileStore(directory: url)
        XCTAssertEqual(try store.read(lockKey: value.lockKey, realm: value.realm, accountID: value.accountID), value)
        XCTAssertTrue(try store.contains(lockKey: value.lockKey))
    }
    func testSameScopeCannotBeReplacedByDifferentRequestAndOldBytesRemain() throws {
        let store = ClubSeriesOriginalRequestFileStore(directory: try directory()), value = try original()
        try store.reserve(value)
        XCTAssertThrowsError(try store.reserve(original(requestID: "replacement")))
        XCTAssertThrowsError(try store.reserve(value))
        XCTAssertEqual(try store.read(lockKey: value.lockKey, realm: value.realm, accountID: 9), value)
    }
    func testWrongAccountOrRealmCannotReadRetainedInput() throws {
        let store = ClubSeriesOriginalRequestFileStore(directory: try directory()), value = try original()
        try store.reserve(value)
        XCTAssertThrowsError(try store.read(lockKey: value.lockKey, realm: "other", accountID: 9))
        XCTAssertThrowsError(try store.read(lockKey: value.lockKey, realm: value.realm, accountID: 10))
    }
    func testUnknownVersionAndDamagedFileStayLockedNotMissing() throws {
        for content in [Data("pending".utf8), try JSONEncoder().encode(original()).replacingVersionForFixture()] {
            let url = try directory(), value = try original(), store = ClubSeriesOriginalRequestFileStore(directory: url)
            try store.reserve(value)
            let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).first)
            try content.write(to: file)
            XCTAssertTrue(try store.contains(lockKey: value.lockKey))
            XCTAssertThrowsError(try store.read(lockKey: value.lockKey, realm: value.realm, accountID: 9))
        }
    }
    func testAbsentNewFileDoesNotMigrateLegacyPending() throws {
        let url = try directory(), value = try original()
        try Data("pending".utf8).write(to: url.appendingPathComponent("legacy.pending"))
        let store = ClubSeriesOriginalRequestFileStore(directory: url)
        XCTAssertNil(try store.read(lockKey: value.lockKey, realm: value.realm, accountID: 9))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("legacy.pending")), Data("pending".utf8))
    }
}
private extension Data {
    func replacingVersionForFixture() throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
        object["version"] = 2
        return try JSONSerialization.data(withJSONObject: object)
    }
}
