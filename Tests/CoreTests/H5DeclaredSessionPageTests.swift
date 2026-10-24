import XCTest
@testable import QuestifyCore

final class H5DeclaredSessionPageTests: XCTestCase {
    func testPageComparesTheServerHashAndImportsMetadataWithoutOpening() throws {
        var page = H5DeclaredSessionPage()
        let hash = String(repeating: "ab", count: 32)
        let frozen = try XCTUnwrap(H5FrozenCapability(
            signedDomains: ["play.chengyin.test"], sdkCapabilities: ["answer"],
            packageVersion: "1.0.0", contentHash: hash))
        try page.admit(host: "play.chengyin.test", capability: "answer", sdkVersion: "1.0.0", frozen: frozen)
        try page.compareServerHash(serverFrozenHash: hash, expectedHash: hash, originalRequestID: "h5-answer-0001")
        XCTAssertEqual(page.rejectClientAnswers(["answer": "hidden"]), .answersMustNotShipInClientPack)
        XCTAssertEqual(page.session.answers.originalRequestID, "h5-answer-0001")
        let object = ["id": "mod-1", "version": "1.0.0", "contentHash": hash, "schemaVersion": "1"]
        try page.importMetadata(object, entry: "mod-1", originalRequestID: "import-req-0001")
        XCTAssertEqual(page.imports.gate.phase, .reviewPending)
        XCTAssertThrowsError(try page.importMetadata(object.merging(["answer": "secret"]) { _, new in new },
                                                     entry: "mod-2", originalRequestID: "import-req-0002"))
        XCTAssertEqual(page.imports.gate.originalRequestID, "import-req-0001")
        XCTAssertEqual(page.open(), .waitingSource(capability: "h5.sdk.original"))
    }
}
