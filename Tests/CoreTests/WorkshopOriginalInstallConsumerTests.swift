import XCTest
@testable import QuestifyCore

final class WorkshopOriginalInstallConsumerTests: XCTestCase {
    private let requestID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private var identity: WorkshopInstallIdentity {
        WorkshopInstallIdentity(licenseId: "lic-1", moduleId: "mod-1", releaseId: "rel-1",
            contentHash: String(repeating: "ab", count: 32), termsHash: String(repeating: "cd", count: 32))!
    }

    func testCanonicalUUIDRequestReadsOriginalReceipt() async throws {
        let source = InstallRead(fact: WorkshopOriginalInstallFact(requestID: requestID, state: "INSTALLED_PRIVATE_DRAFT"))
        let fact = try await WorkshopOriginalInstallConsumer().read(requestID: requestID, identity: identity, source: source)
        XCTAssertEqual(fact.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(source.requestIDs, [requestID])
        XCTAssertEqual(source.identities.first?.licenseId, "lic-1")
        XCTAssertEqual(source.identities.first?.contentHash, String(repeating: "ab", count: 32))
    }

    func testNonUUIDDoesNotReadAndMissingReceiptThrows() async throws {
        let source = InstallRead(fact: nil)
        do {
            _ = try await WorkshopOriginalInstallConsumer().read(requestID: "req-c10-install", identity: identity, source: source)
            XCTFail("non-uuid")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        do {
            _ = try await WorkshopOriginalInstallConsumer().read(requestID: requestID, identity: identity, source: source)
            XCTFail("missing")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .unknown)
        }
        XCTAssertThrowsError(try WorkshopOriginalInstallConsumer().rejectSelfReport(requestID: requestID)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
    }
}

private final class InstallRead: WorkshopOriginalInstallReading, @unchecked Sendable {
    var fact: WorkshopOriginalInstallFact?
    var requestIDs: [String] = []
    var identities: [WorkshopInstallIdentity] = []
    init(fact: WorkshopOriginalInstallFact?) { self.fact = fact }
    func request(_ requestID: String, identity: WorkshopInstallIdentity) async throws -> WorkshopOriginalInstallFact {
        requestIDs.append(requestID)
        identities.append(identity)
        guard let fact, fact.requestID == requestID else { throw WorkshopOriginalInstallError.unknown }
        return fact
    }
}
