import XCTest
@testable import QuestifyCore

final class WorkshopInstallReadEntryTests: XCTestCase {
    private let requestID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

    func testReadUsesTheOriginalReceiptAndPageClearDoesNotInstall() async throws {
        let identity = try XCTUnwrap(WorkshopInstallIdentity(
            licenseId: "lic-1", moduleId: "mod-1", releaseId: "rel-1",
            contentHash: String(repeating: "ab", count: 32),
            termsHash: String(repeating: "cd", count: 32)))
        let source = InstallRead(fact: WorkshopOriginalInstallFact(requestID: requestID, state: "PREPARED"))
        let entry = WorkshopInstallReadEntry()
        let fact = try await entry.read(requestID: requestID, identity: identity, source: source)
        XCTAssertEqual(fact.state, "PREPARED")
        XCTAssertEqual(fact.requestID, requestID)
        XCTAssertThrowsError(try entry.rejectPageClear(requestID: requestID)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(source.requestIDs, [requestID])
    }
}

private final class InstallRead: WorkshopOriginalInstallReading, @unchecked Sendable {
    let fact: WorkshopOriginalInstallFact?
    var requestIDs: [String] = []
    init(fact: WorkshopOriginalInstallFact?) { self.fact = fact }
    func request(_ requestID: String, identity: WorkshopInstallIdentity) async throws -> WorkshopOriginalInstallFact {
        requestIDs.append(requestID)
        _ = identity
        guard let fact else { throw WorkshopOriginalInstallError.unknown }
        return fact
    }
}
