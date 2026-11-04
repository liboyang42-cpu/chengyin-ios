import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class H5LaunchIssuerTests: XCTestCase {
    private let ownedID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let authorID = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let fixtureContentHash = String(repeating: "ab", count: 32)
    private let terms = String(repeating: "cd", count: 32)

    func testMissingConfigurationClosesOnlyTheLaunchAndTheReceiptStaysReadable() async throws {
        var issuer = try released(configuration: nil)
        XCTAssertNil(issuer.issue())
        XCTAssertEqual(issuer.launchClosed, .missingConfiguration)
        XCTAssertNil(issuer.presentedLaunch)
        XCTAssertNil(issuer.presentedShellURL)
        XCTAssertFalse(issuer.parent.shellLoaded)
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        let again = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        XCTAssertEqual(read, again)
        XCTAssertEqual(again.requestID, ownedID)
        XCTAssertNotEqual(again.requestID, authorID)
        XCTAssertEqual(again.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(issuer.receipt, again)
        XCTAssertEqual(source.requestIDs, [ownedID, ownedID])
        XCTAssertFalse(issuer.parent.shellLoaded)
        XCTAssertEqual(issuer.entry.release.journey.machine.installCount, 0)
        XCTAssertThrowsError(try issuer.rejectSelfReportClear()) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(issuer.receipt, again)
        XCTAssertFalse(issuer.clientResultInstalled(["score": "9", "rewardId": "prize"]))
        XCTAssertFalse(issuer.clientResultIsServerPass)
        XCTAssertFalse(issuer.opensZip)
        XCTAssertEqual(issuer.entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(issuer.entry.registerPublic(), .publicRegistryReserved)
    }

    func testNonHTTPSClosesOnlyTheLaunch() async throws {
        var issuer = try released(configuration: nil)
        let http = try XCTUnwrap(URL(string: "http://api.example.test/prod-api"))
        XCTAssertNil(issuer.issue(baseURL: http))
        XCTAssertEqual(issuer.launchClosed, .notHTTPS)
        XCTAssertNil(issuer.presentedLaunch)
        XCTAssertNil(issuer.presentedShellURL)
        XCTAssertFalse(issuer.parent.shellLoaded)
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertFalse(issuer.parent.shellLoaded)
        XCTAssertEqual(issuer.entry.release.journey.machine.installCount, 0)
    }

    func testUserinfoDoesNotBecomeTheOrigin() async throws {
        var issuer = try released(configuration: nil)
        let credentialed = try XCTUnwrap(URL(string: "https://user:secret@api.example.test/prod-api"))
        XCTAssertNil(issuer.issue(baseURL: credentialed))
        XCTAssertEqual(issuer.launchClosed, .hostMismatch)
        XCTAssertNil(issuer.presentedLaunch)
        XCTAssertNil(issuer.presentedShellURL)
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertFalse(issuer.parent.shellLoaded)
        XCTAssertFalse(issuer.opensZip)
    }

    func testAPIConfigurationCannotMintTicketOrLoadAPIDomain() async throws {
        for text in ["https://api.example.test/prod-api", "https://api.example.test:8443/prod-api"] {
            let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: text)))
            var issuer = try released(configuration: configuration)
            for _ in 0..<3 {
                XCTAssertNil(issuer.issue())
                XCTAssertEqual(issuer.launchClosed, .serverIssuedLaunchUnavailable)
                XCTAssertNil(issuer.presentedLaunch)
                XCTAssertNil(issuer.presentedShellURL)
                XCTAssertFalse(issuer.parent.shellLoaded)
            }
            let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
            let read = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
            let again = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
            XCTAssertEqual(read, again)
            XCTAssertEqual(source.requestIDs, [ownedID, ownedID])
            XCTAssertEqual(issuer.receipt, read)
            XCTAssertFalse(issuer.parent.shellLoaded)
            XCTAssertFalse(issuer.clientResultIsServerPass)
            XCTAssertFalse(issuer.clientResultInstalled(["SUCCESS": "true", "score": "999"]))
            XCTAssertEqual(issuer.entry.release.journey.machine.installCount, 0)
            XCTAssertThrowsError(try issuer.rejectSelfReportClear())
            XCTAssertEqual(issuer.receipt, read)
        }
    }

    func testClosedLaunchKeepsUnknownOriginalRequestAvailable() async throws {
        let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://api.example.test")))
        var issuer = try released(configuration: configuration)
        let source = IssuerInstallRead(fact: nil)
        do {
            _ = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
            XCTFail("missing original receipt must stay unknown")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .unknown)
        }
        XCTAssertEqual(issuer.launchClosed, .serverIssuedLaunchUnavailable)
        XCTAssertNil(issuer.receipt)
        XCTAssertFalse(issuer.parent.shellLoaded)
        source.fact = try fact(ownedID, "INSTALLED_PRIVATE_DRAFT")
        let recovered = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        XCTAssertEqual(recovered.requestID, ownedID)
        XCTAssertEqual(source.requestIDs, [ownedID, ownedID])
        XCTAssertEqual(issuer.entry.release.journey.machine.installCount, 0)
    }

    func testAdvancedStartAndPaymentContextAreNotTickets() async throws {
        var issuer = try released(configuration: try APIConfiguration(baseURL: try XCTUnwrap(URL(string: "https://api.example.test/api/play/advanced/start"))))
        XCTAssertNil(issuer.issue())
        XCTAssertEqual(issuer.launchClosed, .advancedStartRefused)
        XCTAssertNil(issuer.refuseAdvancedStart(.init(activityID: 41, topicID: 71, nodeID: 701)))
        XCTAssertNil(issuer.presentedLaunch)
        issuer = try released(configuration: try APIConfiguration(baseURL: try XCTUnwrap(URL(string: "https://api.example.test/orders/native-context"))))
        XCTAssertNil(issuer.issue())
        XCTAssertEqual(issuer.launchClosed, .paymentNativeContextRefused)
        XCTAssertNil(issuer.refusePaymentNativeContext(.init(values: ["nativeContext": "signed"])))
        let configuration = try APIConfiguration(baseURL: try XCTUnwrap(URL(string: "https://api.example.test/prod-api")))
        var opened = try released(configuration: configuration)
        XCTAssertNil(opened.issue())
        XCTAssertNil(opened.refuseAdvancedStart(.init(activityID: 41, topicID: 71, nodeID: 701)))
        XCTAssertNil(opened.presentedShellURL)
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await opened.readOwnedInstallReceipt(identity: opened.owned.identity, source: source)
        XCTAssertEqual(read.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertFalse(opened.parent.shellLoaded)
        XCTAssertFalse(issuer.parent.shellLoaded)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertEqual(opened.entry.release.journey.machine.installCount, 0)
    }

    func testUnreadReleaseDoesNotInventApproval() async throws {
        let configuration = try APIConfiguration(baseURL: try XCTUnwrap(URL(string: "https://api.example.test/prod-api")))
        var issuer = try XCTUnwrap(H5LaunchIssuer(owned: try owned(), author: try author(), configuration: configuration,
                                                 entry: WorkshopInstallRecoverEntry()))
        XCTAssertNil(issuer.issue())
        let source = IssuerInstallRead(fact: try fact(ownedID, "PREPARED"))
        do {
            _ = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
            XCTFail("approval")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(issuer.receipt)
        XCTAssertFalse(issuer.entry.release.released)
        XCTAssertEqual(issuer.entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(issuer.entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(issuer.entry.registerPublic(), .publicRegistryReserved)
    }

    func testWrongIdentityIsNotRead() async throws {
        var issuer = try released(configuration: nil)
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let other = try XCTUnwrap(WorkshopInstallIdentity(
            licenseId: "lic-2", moduleId: "mod-1", releaseId: "rel-1", contentHash: fixtureContentHash, termsHash: terms))
        do {
            _ = try await issuer.readOwnedInstallReceipt(identity: other, source: source)
            XCTFail("identity")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(issuer.receipt)
        XCTAssertNil(H5LaunchIssuer(owned: try owned(), author: try XCTUnwrap(H5LaunchIssuer.AuthorSubmission(requestID: ownedID)),
                                   configuration: nil))
        XCTAssertNil(H5LaunchIssuer.LicenseInstall(
            requestID: ownedID, licenseId: "lic-1", moduleId: "mod-1", purchasedVersionId: "rel-1",
            contentHash: fixtureContentHash, termsHash: terms, status: "SUSPENDED"))
        XCTAssertNil(H5LaunchIssuer.AuthorSubmission(requestID: "not-a-request"))
        XCTAssertNil(H5LaunchDescription(parentOrigin: "https://api.example.test", nonce: "abc", mainToken: "session-token"))
    }

    private func released(configuration: APIConfiguration?) throws -> H5LaunchIssuer {
        var entry = WorkshopInstallRecoverEntry()
        try entry.submitManifest(manifest(fixtureContentHash), entry: "mod-1", originalRequestID: ownedID)
        try entry.releaseReviewed(termsHash: terms, reviewed: true)
        return try XCTUnwrap(H5LaunchIssuer(owned: try owned(), author: try author(), configuration: configuration, entry: entry))
    }

    private func owned() throws -> H5LaunchIssuer.LicenseInstall {
        try XCTUnwrap(H5LaunchIssuer.LicenseInstall(
            requestID: ownedID, licenseId: "lic-1", moduleId: "mod-1", purchasedVersionId: "rel-1",
            contentHash: fixtureContentHash, termsHash: terms, status: "ACTIVE"))
    }

    private func author() throws -> H5LaunchIssuer.AuthorSubmission {
        try XCTUnwrap(H5LaunchIssuer.AuthorSubmission(requestID: authorID))
    }

    private func fact(_ requestID: String, _ state: String) throws -> WorkshopOriginalInstallFact {
        try XCTUnwrap(WorkshopOriginalInstallFact(requestID: requestID, state: state))
    }

    private func manifest(_ fixtureContentHash: String) -> [String: String] {
        ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
         "packageVersion": "1.0.0", "entrypoint": "content.json", "contentHash": fixtureContentHash,
         "schemaVersion": "1", "filePath": "content.json", "fileSha256": fixtureContentHash, "fileBytes": "12"]
    }
}

private final class IssuerInstallRead: WorkshopOriginalInstallReading, @unchecked Sendable {
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
