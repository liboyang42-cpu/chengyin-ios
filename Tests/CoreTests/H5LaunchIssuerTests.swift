import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class H5LaunchIssuerTests: XCTestCase {
    private let ownedID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let authorID = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let hash = String(repeating: "ab", count: 32)
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

    func testHeldHostMintsNonceAndParentReadsTheOwnedReceipt() async throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.test/prod-api"))
        let configuration = try APIConfiguration(baseURL: base)
        var issuer = try released(configuration: configuration)
        let request = try XCTUnwrap(issuer.issue())
        let launch = try XCTUnwrap(issuer.presentedLaunch)
        let shell = try XCTUnwrap(issuer.presentedShellURL)
        let host = try XCTUnwrap(base.host)
        let shellHost = try XCTUnwrap(shell.host)
        XCTAssertNil(issuer.launchClosed)
        XCTAssertEqual(launch.parentOrigin, "https://\(host)")
        XCTAssertEqual(shellHost, host)
        XCTAssertEqual(shell.port, base.port)
        XCTAssertNil(shell.user)
        XCTAssertNil(shell.password)
        XCTAssertFalse(launch.parentOrigin.contains("@"))
        XCTAssertFalse(launch.parentOrigin.contains("prod-api"))
        XCTAssertFalse(shell.absoluteString.contains("prod-api"))
        XCTAssertEqual(shellHost.split(separator: ".").count, host.split(separator: ".").count)
        XCTAssertNotEqual(shellHost, "shell." + host)
        XCTAssertEqual(request.url?.host, base.host)
        XCTAssertEqual(request.url?.port, base.port)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertNil(request.url?.query)
        XCTAssertNil(request.url?.fragment)
        XCTAssertEqual(launch.nonce.count, 32)
        XCTAssertNotNil(launch.nonce.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
        XCTAssertEqual(String(data: request.httpBody ?? Data(), encoding: .utf8), "nonce=\(launch.nonce)")
        XCTAssertFalse((request.url?.absoluteString ?? "").contains(launch.nonce))
        XCTAssertFalse((request.httpBody ?? Data()).contains(ownedID.data(using: .utf8)!))
        XCTAssertFalse((request.httpBody ?? Data()).contains(authorID.data(using: .utf8)!))
        XCTAssertFalse((request.httpBody ?? Data()).contains("token".data(using: .utf8)!))
        XCTAssertFalse(issuer.parent.shellLoaded)
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        XCTAssertTrue(issuer.parent.shellLoaded)
        XCTAssertEqual(issuer.parent.receipt, read)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertEqual(issuer.entry.release.journey.machine.installCount, 0)
        XCTAssertFalse(issuer.opensZip)
        XCTAssertEqual(issuer.entry.registerPublic(), .publicRegistryReserved)
        let first = launch.nonce
        let again = try XCTUnwrap(issuer.issue())
        let second = try XCTUnwrap(issuer.presentedLaunch?.nonce)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(String(data: again.httpBody ?? Data(), encoding: .utf8), "nonce=\(second)")
    }

    func testExplicitPortStaysOnTheSameHost() async throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.test:8443/prod-api"))
        var issuer = try released(configuration: try APIConfiguration(baseURL: base))
        let request = try XCTUnwrap(issuer.issue())
        XCTAssertEqual(issuer.presentedLaunch?.parentOrigin, "https://api.example.test:8443")
        XCTAssertEqual(request.url?.host, "api.example.test")
        XCTAssertEqual(request.url?.port, 8443)
        XCTAssertEqual(issuer.presentedShellURL?.host, base.host)
        XCTAssertFalse(request.url?.absoluteString.contains("prod-api") ?? true)
    }

    func testDifferentHostDoesNotLoad() async throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.test/prod-api"))
        var issuer = try released(configuration: try APIConfiguration(baseURL: base))
        XCTAssertNotNil(issuer.issue())
        let launch = try XCTUnwrap(issuer.presentedLaunch)
        let other = try XCTUnwrap(URL(string: "https://evil.example/shell"))
        XCTAssertNil(H5ShellParentFlow.loadRequest(shellURL: other, launch: launch))
        XCTAssertNil(issuer.parent.open(shellURL: other, launch: launch))
        XCTAssertFalse(issuer.parent.shellLoaded)
        XCTAssertNil(H5ShellParentFlow.loadRequest(shellURL: try XCTUnwrap(URL(string: "http://api.example.test/")), launch: launch))
        XCTAssertNil(H5ShellParentFlow.loadRequest(shellURL: try XCTUnwrap(URL(string: "https://user:secret@api.example.test/")), launch: launch))
        XCTAssertNil(H5ShellParentFlow.loadRequest(shellURL: try XCTUnwrap(URL(string: "https://api.example.test:8443/")), launch: launch))
        let source = IssuerInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await issuer.readOwnedInstallReceipt(identity: issuer.owned.identity, source: source)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertEqual(issuer.presentedShellURL?.host, base.host)
        XCTAssertTrue(issuer.parent.shellLoaded)
        XCTAssertEqual(source.requestIDs, [ownedID])
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
        XCTAssertNotNil(opened.issue())
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
        XCTAssertNotNil(issuer.issue())
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
            licenseId: "lic-2", moduleId: "mod-1", releaseId: "rel-1", contentHash: hash, termsHash: terms))
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
            contentHash: hash, termsHash: terms, status: "SUSPENDED"))
        XCTAssertNil(H5LaunchIssuer.AuthorSubmission(requestID: "not-a-request"))
        XCTAssertNil(H5LaunchDescription(parentOrigin: "https://api.example.test", nonce: "abc", mainToken: "session-token"))
    }

    private func released(configuration: APIConfiguration?) throws -> H5LaunchIssuer {
        var entry = WorkshopInstallRecoverEntry()
        try entry.submitManifest(manifest(hash), entry: "mod-1", originalRequestID: ownedID)
        try entry.releaseReviewed(termsHash: terms, reviewed: true)
        return try XCTUnwrap(H5LaunchIssuer(owned: try owned(), author: try author(), configuration: configuration, entry: entry))
    }

    private func owned() throws -> H5LaunchIssuer.LicenseInstall {
        try XCTUnwrap(H5LaunchIssuer.LicenseInstall(
            requestID: ownedID, licenseId: "lic-1", moduleId: "mod-1", purchasedVersionId: "rel-1",
            contentHash: hash, termsHash: terms, status: "ACTIVE"))
    }

    private func author() throws -> H5LaunchIssuer.AuthorSubmission {
        try XCTUnwrap(H5LaunchIssuer.AuthorSubmission(requestID: authorID))
    }

    private func fact(_ requestID: String, _ state: String) throws -> WorkshopOriginalInstallFact {
        try XCTUnwrap(WorkshopOriginalInstallFact(requestID: requestID, state: state))
    }

    private func manifest(_ hash: String) -> [String: String] {
        ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
         "packageVersion": "1.0.0", "entrypoint": "content.json", "contentHash": hash,
         "schemaVersion": "1", "filePath": "content.json", "fileSha256": hash, "fileBytes": "12"]
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
