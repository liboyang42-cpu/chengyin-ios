import XCTest
@testable import QuestifyCore

final class WorkshopInstallRecoverEntryTests: XCTestCase {
    private let requestID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let otherID = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"

    func testReviewedReleaseReadsTheSameReceiptAndSelfReportDoesNotInstall() async throws {
        var entry = WorkshopInstallRecoverEntry()
        let hash = String(repeating: "ab", count: 32)
        let terms = String(repeating: "cd", count: 32)
        let identity = try XCTUnwrap(WorkshopInstallIdentity(
            licenseId: "lic-1", moduleId: "mod-1", releaseId: "rel-1",
            contentHash: hash, termsHash: terms))
        let source = RecoverRead(fact: WorkshopOriginalInstallFact(requestID: requestID, state: "INSTALLED_PRIVATE_DRAFT"))
        try entry.submitManifest(manifest(hash), entry: "mod-1", originalRequestID: requestID)
        XCTAssertFalse(entry.release.released)
        XCTAssertFalse(entry.release.ownsCopyright)
        XCTAssertFalse(entry.release.publishRight)
        XCTAssertFalse(entry.opensZip)
        XCTAssertFalse(entry.clientResultIsServerPass)
        XCTAssertThrowsError(try entry.install()) { XCTAssertEqual($0 as? WorkshopInstallFailure, .invalidGrant) }
        do {
            _ = try await entry.recover(requestID: requestID, identity: identity, source: source)
            XCTFail("declaration")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertThrowsError(try entry.releaseReviewed(termsHash: terms, reviewed: false)) {
            XCTAssertEqual($0 as? WorkshopPackagePublishFailure, .notReviewed)
        }
        try entry.releaseReviewed(termsHash: terms, reviewed: true)
        XCTAssertTrue(entry.release.released)
        XCTAssertThrowsError(try entry.rejectPageClear(requestID: requestID)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertThrowsError(try entry.rejectJavaScriptClear(requestID: requestID)) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(entry.release.journey.machine.phase, .idle)
        XCTAssertNotEqual(entry.answers.phase, .matched)
        try entry.install()
        try entry.installAgain()
        XCTAssertEqual(entry.release.journey.machine.installCount, 1)
        let wrong = try XCTUnwrap(WorkshopInstallIdentity(
            licenseId: "lic-1", moduleId: "mod-2", releaseId: "rel-1",
            contentHash: hash, termsHash: terms))
        do {
            _ = try await entry.readReceipt(requestID: requestID, identity: wrong, source: source)
            XCTFail("identity")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        do {
            _ = try await entry.readReceipt(requestID: otherID, identity: identity, source: source)
            XCTFail("request")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        let read = try await entry.readReceipt(requestID: requestID, identity: identity, source: source)
        let recovered = try await entry.recover(requestID: requestID, identity: identity, source: source)
        let again = try await entry.recover(requestID: requestID, identity: identity, source: source)
        XCTAssertEqual(read, recovered)
        XCTAssertEqual(again, recovered)
        XCTAssertEqual(again.requestID, requestID)
        XCTAssertEqual(again.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(source.requestIDs, [requestID, requestID, requestID])
        XCTAssertFalse(entry.recordClientResult(["score": "9", "rewardId": "prize"]))
        XCTAssertEqual(entry.receipt, recovered)
        XCTAssertEqual(entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertFalse(entry.opensZip)
        XCTAssertEqual(entry.registerPublic(), .publicRegistryReserved)
        XCTAssertThrowsError(try entry.rejectPageClear(requestID: requestID)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(entry.release.journey.machine.installCount, 1)
        XCTAssertEqual(entry.release.journey.machine.phase, .installed)
        XCTAssertEqual(entry.receipt, recovered)
    }

    func testChangedReceiptForTheSameRequestIsNotInstalled() async throws {
        var entry = try released()
        let identity = try installedIdentity()
        let source = RecoverRead(fact: WorkshopOriginalInstallFact(requestID: requestID, state: "PREPARED"))
        let first = try await entry.recover(requestID: requestID, identity: identity, source: source)
        XCTAssertEqual(first.state, "PREPARED")
        source.fact = WorkshopOriginalInstallFact(requestID: requestID, state: "FAILED")
        do {
            _ = try await entry.recover(requestID: requestID, identity: identity, source: source)
            XCTFail("changed")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .unknown)
        }
        XCTAssertEqual(source.requestIDs, [requestID, requestID])
        XCTAssertEqual(entry.receipt, first)
        XCTAssertEqual(entry.release.journey.machine.installCount, 0)
        XCTAssertFalse(entry.clientResultIsServerPass)
        XCTAssertEqual(entry.registerPublic(), .publicRegistryReserved)
    }

    private func released() throws -> WorkshopInstallRecoverEntry {
        var entry = WorkshopInstallRecoverEntry()
        let hash = String(repeating: "ab", count: 32)
        try entry.submitManifest(manifest(hash), entry: "mod-1", originalRequestID: requestID)
        try entry.releaseReviewed(termsHash: String(repeating: "cd", count: 32), reviewed: true)
        return entry
    }

    private func installedIdentity() throws -> WorkshopInstallIdentity {
        try XCTUnwrap(WorkshopInstallIdentity(
            licenseId: "lic-1", moduleId: "mod-1", releaseId: "rel-1",
            contentHash: String(repeating: "ab", count: 32),
            termsHash: String(repeating: "cd", count: 32)))
    }

    private func manifest(_ hash: String) -> [String: String] {
        ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
         "packageVersion": "1.0.0", "entrypoint": "content.json", "contentHash": hash,
         "schemaVersion": "1", "filePath": "content.json", "fileSha256": hash, "fileBytes": "12"]
    }
}

private final class RecoverRead: WorkshopOriginalInstallReading, @unchecked Sendable {
    var fact: WorkshopOriginalInstallFact?
    var requestIDs: [String] = []
    init(fact: WorkshopOriginalInstallFact?) { self.fact = fact }
    func request(_ requestID: String, identity: WorkshopInstallIdentity) async throws -> WorkshopOriginalInstallFact {
        requestIDs.append(requestID)
        _ = identity
        guard let fact, fact.requestID == requestID else { throw WorkshopOriginalInstallError.unknown }
        return fact
    }
}
