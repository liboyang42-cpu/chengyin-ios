import Foundation
import XCTest
@testable import QuestifyCore

final class ClubSeriesRequestIDContractTests: XCTestCase {
    private func command(_ id: String) throws -> ClubGovernanceCommand {
        try ClubGovernanceCommand(operation: .createSeries, scope: .init(clubID: 7, topicID: 8), values: [
            "requestId": .string(id), "recurrenceType": .string("ONCE"), "startDate": .string("2026-11-07"),
            "startTime": .string("09:00"), "occurrenceCount": .integer(1), "customDates": .null,
            "capacity": .null, "defaultLeadMemberId": .null, "waitlistEnabled": .bool(true), "offerMinutes": .integer(1440)])
    }
    func testJavaTrimBoundaryKeepsExactWireValue() throws {
        let id = "\u{0000}\t " + String(repeating: "a", count: 64) + "\r\n\u{001F}"
        XCTAssertEqual(try command(id).fields["requestId"], .string(id))
        XCTAssertThrowsError(try command(String(repeating: "a", count: 65)))
        XCTAssertThrowsError(try command(" \t\u{0000}\n"))
    }
    func testUTF16LengthNotGraphemeCount() throws {
        XCTAssertNoThrow(try command(String(repeating: "😀", count: 32)))
        XCTAssertThrowsError(try command(String(repeating: "😀", count: 33)))
        XCTAssertNoThrow(try command(String(repeating: "e\u{0301}", count: 32)))
        XCTAssertThrowsError(try command(String(repeating: "e\u{0301}", count: 33)))
    }
    func testUnicodeWhitespaceIsNotJavaTrim() throws {
        XCTAssertEqual(try command("\u{00A0}").fields["requestId"], .string("\u{00A0}"))
        XCTAssertThrowsError(try command("\u{00A0}" + String(repeating: "a", count: 64)))
        XCTAssertThrowsError(try command("\u{2003}" + String(repeating: "a", count: 64)))
    }
    func testNormalGeneratedIDAndOtherOperationsAreUnchanged() throws {
        let id = "club-native-" + UUID().uuidString
        XCTAssertEqual(try command(id).fields["requestId"], .string(id))
        let other = try ClubGovernanceCommand(operation: .saveCustomer, scope: .init(clubID: 7, memberID: 9),
            values: ["requestId": .string(String(repeating: "a", count: 65)), "tags": .array([]), "remark": .string("")])
        XCTAssertEqual(other.fields["requestId"]?.string?.count, 65)
    }
    @MainActor func testHistoricalInvalidRequestRemainsLockedAndBytesUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try ClubSeriesOriginalRequest(realm: "fixture", accountID: 9, lockKey: "fixture-lock", command: command("valid"))
        let store = ClubSeriesOriginalRequestFileStore(directory: directory)
        try store.reserve(original)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var fields = try XCTUnwrap(object["fields"] as? [String: Any])
        fields["requestId"] = String(repeating: "a", count: 65); object["fields"] = fields
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: file)
        XCTAssertThrowsError(try store.read(lockKey: original.lockKey, realm: "fixture", accountID: 9))
        XCTAssertTrue(try store.contains(lockKey: original.lockKey))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
