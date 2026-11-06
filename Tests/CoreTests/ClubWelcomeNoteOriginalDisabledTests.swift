import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ClubWelcomeNoteOriginalDisabledTests: XCTestCase {
    private final class OrdinaryAccess: ClubOperationsAccess {
        var identity: ClubReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured: Bool { true }
        var writeAvailability: ClubOperationsWriteAvailability { .approved }
        var reads = 0
        var writes = 0
        func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot {
            reads += 1
            throw APIError.notConfigured
        }
        func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget,
                     expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
            writes += 1
            throw APIError.notConfigured
        }
    }
    func testOrdinaryApprovalNeverProvidesWelcomeWriterOrRecovery() async {
        let access = OrdinaryAccess()
        XCTAssertNil(access.welcomeNote)
        let flow = ClubWelcomeNoteFlow(clubID: 9, identity: access.identity!, access: access)
        flow.draft = "Example"
        XCTAssertFalse(flow.canSave)
        await flow.save()
        XCTAssertEqual(access.writes, 0)
        await flow.load()
        XCTAssertEqual(access.reads, 1)
        XCTAssertEqual(flow.state, .unavailable)
        XCTAssertTrue(flow.originalResults.isEmpty)
        XCTAssertFalse(flow.canSave)
        flow.close()
        XCTAssertTrue(flow.draft.isEmpty)
        await flow.load()
        XCTAssertEqual(access.reads, 1)
    }
    func testOriginalUnicodeScalarLimitAndClearSemantics() throws {
        XCTAssertEqual(try ClubWelcomeNoteService.normalized(" \n"), "")
        XCTAssertEqual(try ClubWelcomeNoteService.normalized("  hello  "), "hello")
        let decomposed = String(repeating: "e\u{301}", count: 100)
        XCTAssertEqual(try ClubWelcomeNoteService.normalized(decomposed), decomposed)
        XCTAssertThrowsError(try ClubWelcomeNoteService.normalized(decomposed + "x"))
    }
}
