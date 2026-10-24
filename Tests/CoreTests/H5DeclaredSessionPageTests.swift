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
        XCTAssertEqual(page.openShell(launch: nil), .waitingLaunchTicket)
        let launch = try XCTUnwrap(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce-1", mainToken: nil))
        XCTAssertNil(H5LaunchDescription(parentOrigin: "https://shell.chengyin.test", nonce: "nonce-1", mainToken: "session-token"))
        XCTAssertEqual(page.openShell(launch: launch), .shellReady)
        let request = "fb5e2418-9eb0-4e43-94e6-c8c951a7d1cf"
        XCTAssertEqual(page.receive(protocolVersion: "1.0", requestID: request, sequence: 1,
                                    method: "result.submit", payload: ["score": "9"]), .rejected("h5.resultRejected"))
        XCTAssertEqual(page.receive(protocolVersion: "1.0", requestID: request, sequence: 1,
                                    method: "result.submit", payload: ["challengeId": "challenge.demo.001"]), .resultSubmitted)
        XCTAssertFalse(page.host.passed)
        XCTAssertEqual(page.receive(protocolVersion: "1.0", requestID: request, sequence: 2,
                                    method: "getToken", payload: [:]), .rejected("h5.methodForbidden"))
    }
}
