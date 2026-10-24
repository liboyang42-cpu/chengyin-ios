import XCTest
@testable import QuestifyCore

final class H5DeclaredSessionEntryTests: XCTestCase {
    func testDeclaredSurfaceAdmitsAndOpenStaysWaiting() throws {
        var entry = H5DeclaredSessionEntry()
        let frozen = try XCTUnwrap(H5FrozenCapability(
            signedDomains: ["play.chengyin.test"],
            sdkCapabilities: ["answer"],
            packageVersion: "1.0.0",
            contentHash: String(repeating: "ab", count: 32)))
        try entry.admit(host: "play.chengyin.test", capability: "answer", sdkVersion: "1.0.0", frozen: frozen)
        XCTAssertEqual(entry.gate.phase, .admitted)
        let opened = entry.open()
        XCTAssertEqual(opened, .waitingSource(capability: "h5.sdk.original"))
        XCTAssertEqual(entry.gate.phase, .waitingSource)
        XCTAssertThrowsError(try entry.gate.openArbitraryH5("https://evil.example")) { error in
            XCTAssertEqual(error as? H5SessionFailure, .arbitraryH5Forbidden)
        }
        let hash = String(repeating: "ab", count: 32)
        try entry.compareServerHash(serverFrozenHash: hash, expectedHash: hash, originalRequestID: "h5-answer-0001")
        XCTAssertEqual(entry.answers.phase, .matched)
        XCTAssertEqual(entry.answers.originalRequestID, "h5-answer-0001")
        XCTAssertEqual(entry.rejectClientAnswers(["answer": "hidden"]), .answersMustNotShipInClientPack)
        XCTAssertEqual(entry.answers.originalRequestID, "h5-answer-0001")
        XCTAssertEqual(entry.answers.matchedHash, hash)
    }
}
