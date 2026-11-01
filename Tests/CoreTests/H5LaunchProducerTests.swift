import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class H5LaunchProducerTests: XCTestCase {
    private let ownedID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let authorID = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let origin = "https://shell.chengyin.test"
    private let hash = String(repeating: "ab", count: 32)
    private let terms = String(repeating: "cd", count: 32)

    func testAbsentLaunchFieldsStayClosedAndTheReceiptStaysReadable() async throws {
        var producer = try releasedProducer()
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .missingLaunchFields)
        XCTAssertNil(producer.presentedLaunch)
        XCTAssertNil(producer.presentedShellURL)
        XCTAssertFalse(producer.parent.shellLoaded)
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
        let again = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
        XCTAssertEqual(read, again)
        XCTAssertEqual(again.requestID, ownedID)
        XCTAssertNotEqual(again.requestID, authorID)
        XCTAssertEqual(again.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(producer.receipt, again)
        XCTAssertEqual(producer.entry.receipt, again)
        XCTAssertEqual(source.requestIDs, [ownedID, ownedID])
        XCTAssertFalse(producer.parent.shellLoaded)
        XCTAssertEqual(producer.entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(producer.entry.release.journey.machine.phase, .idle)
        XCTAssertThrowsError(try producer.rejectSelfReportClear()) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(producer.receipt, again)
        XCTAssertFalse(producer.clientResultInstalled(["score": "9", "rewardId": "prize"]))
        XCTAssertFalse(producer.clientResultIsServerPass)
        XCTAssertFalse(producer.opensZip)
        XCTAssertEqual(producer.entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(producer.entry.registerPublic(), .publicRegistryReserved)
    }

    func testSameHostNoncePostThenParentReadsTheOwnedReceipt() async throws {
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var producer = try releasedProducer(ownedLaunch: launch(shell: shell), authorLaunch: launch(shell: shell))
        let request = try XCTUnwrap(producer.produce())
        XCTAssertNil(producer.launchClosed)
        XCTAssertEqual(request.url, shell)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: request.httpBody ?? Data(), encoding: .utf8), "nonce=nonce1")
        XCTAssertFalse((request.httpBody ?? Data()).contains(ownedID.data(using: .utf8)!))
        XCTAssertFalse((request.httpBody ?? Data()).contains(authorID.data(using: .utf8)!))
        XCTAssertFalse((request.httpBody ?? Data()).contains("token".data(using: .utf8)!))
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
        XCTAssertTrue(producer.parent.shellLoaded)
        XCTAssertEqual(producer.parent.receipt, read)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertEqual(producer.entry.release.journey.machine.installCount, 0)
        XCTAssertFalse(producer.opensZip)
        XCTAssertEqual(producer.entry.registerPublic(), .publicRegistryReserved)
    }

    func testAuthorFieldsUseTheOwnedInstallReceipt() async throws {
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/author-shell"))
        var producer = try releasedProducer(authorLaunch: launch(shell: shell, nonce: "authornonce"))
        let request = try XCTUnwrap(producer.produce())
        XCTAssertEqual(String(data: request.httpBody ?? Data(), encoding: .utf8), "nonce=authornonce")
        XCTAssertEqual(request.url, shell)
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertTrue(producer.parent.shellLoaded)
    }

    func testDifferentHostClosesOnlyTheLaunch() async throws {
        var producer = try releasedProducer(ownedLaunch: launch(shell: try XCTUnwrap(URL(string: "https://evil.example/shell"))))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .hostMismatch)
        producer = try releasedProducer(ownedLaunch: launch(shell: try XCTUnwrap(URL(string: "http://shell.chengyin.test/shell"))))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .hostMismatch)
        producer = try releasedProducer(ownedLaunch: launch(shell: try XCTUnwrap(URL(string: "https://user:secret@shell.chengyin.test/shell"))))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .hostMismatch)
        producer = try releasedProducer(ownedLaunch: launch(shell: try XCTUnwrap(URL(string: "https://shell.chengyin.test:8443/shell"))))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .hostMismatch)
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertFalse(producer.parent.shellLoaded)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertEqual(producer.entry.release.journey.machine.installCount, 0)
    }

    func testAdvancedStartAndPaymentContextAreNotTickets() async throws {
        let advanced = try XCTUnwrap(URL(string: "https://shell.chengyin.test/api/play/advanced/start"))
        var producer = try releasedProducer(ownedLaunch: launch(shell: advanced))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .advancedStartRefused)
        XCTAssertNil(producer.refuseAdvancedStart(.init(activityID: 41, topicID: 71, nodeID: 701)))
        XCTAssertNil(producer.presentedLaunch)
        let payment = try XCTUnwrap(URL(string: "https://shell.chengyin.test/orders/native-context"))
        producer = try releasedProducer(ownedLaunch: launch(shell: payment))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .paymentNativeContextRefused)
        XCTAssertNil(producer.refusePaymentNativeContext(.init(values: [
            "parentOrigin": origin, "nonce": "nonce1", "nativeContext": "signed"
        ])))
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var opened = try releasedProducer(ownedLaunch: launch(shell: shell))
        XCTAssertNotNil(opened.produce())
        XCTAssertNil(opened.refuseAdvancedStart(.init(activityID: 41, topicID: 71, nodeID: 701)))
        XCTAssertNil(opened.presentedShellURL)
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await opened.readOriginalReceipt(identity: opened.owned.identity, source: source)
        XCTAssertEqual(read.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertFalse(opened.parent.shellLoaded)
        XCTAssertFalse(producer.parent.shellLoaded)
        XCTAssertEqual(source.requestIDs, [ownedID])
        XCTAssertEqual(opened.entry.release.journey.machine.installCount, 0)
    }

    func testPartialOrDisagreeingFieldsDoNotInventALaunch() async throws {
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var producer = try releasedProducer(ownedLaunch: .init(parentOrigin: nil, nonce: "nonce1", shellURL: nil))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .missingLaunchFields)
        producer = try releasedProducer(ownedLaunch: launch(shell: shell, nonce: "one"),
                                       authorLaunch: launch(shell: shell, nonce: "two"))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .conflictingLaunchFields)
        producer = try releasedProducer(ownedLaunch: launch(shell: shell, mainToken: "session-token"))
        XCTAssertNil(H5LaunchDescription(parentOrigin: origin, nonce: "nonce1", mainToken: "session-token"))
        XCTAssertNil(producer.produce())
        XCTAssertEqual(producer.launchClosed, .missingLaunchFields)
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let read = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
        XCTAssertEqual(read.requestID, ownedID)
        XCTAssertFalse(producer.parent.shellLoaded)
        XCTAssertEqual(producer.entry.release.journey.machine.installCount, 0)
    }

    func testUnreadReleaseDoesNotInventApproval() async throws {
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var producer = try XCTUnwrap(H5LaunchProducer(
            owned: try owned(launch: launch(shell: shell)), author: try author(), entry: WorkshopInstallRecoverEntry()))
        XCTAssertNotNil(producer.produce())
        let source = LaunchInstallRead(fact: try fact(ownedID, "PREPARED"))
        do {
            _ = try await producer.readOriginalReceipt(identity: producer.owned.identity, source: source)
            XCTFail("approval")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(producer.receipt)
        XCTAssertFalse(producer.entry.release.released)
        XCTAssertEqual(producer.entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(producer.entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(producer.entry.registerPublic(), .publicRegistryReserved)
    }

    func testWrongIdentityIsNotRead() async throws {
        var producer = try releasedProducer()
        let source = LaunchInstallRead(fact: try fact(ownedID, "INSTALLED_PRIVATE_DRAFT"))
        let other = try XCTUnwrap(WorkshopInstallIdentity(
            licenseId: "lic-2", moduleId: "mod-1", releaseId: "rel-1", contentHash: hash, termsHash: terms))
        do {
            _ = try await producer.readOriginalReceipt(identity: other, source: source)
            XCTFail("identity")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(producer.receipt)
        let sameAuthor = try XCTUnwrap(H5LaunchProducer.AuthorSubmission(requestID: ownedID))
        XCTAssertNil(H5LaunchProducer(owned: try owned(), author: sameAuthor))
        XCTAssertNil(H5LaunchProducer.OwnedLicenseInstall(
            requestID: ownedID, licenseId: "lic-1", moduleId: "mod-1", purchasedVersionId: "rel-1",
            contentHash: hash, termsHash: terms, status: "SUSPENDED"))
        XCTAssertNil(H5LaunchProducer.AuthorSubmission(requestID: "not-a-request"))
    }

    private func releasedProducer(ownedLaunch: H5LaunchProducer.EntryLaunch = .absent,
                                 authorLaunch: H5LaunchProducer.EntryLaunch = .absent) throws -> H5LaunchProducer {
        var entry = WorkshopInstallRecoverEntry()
        try entry.submitManifest(manifest(hash), entry: "mod-1", originalRequestID: ownedID)
        try entry.releaseReviewed(termsHash: terms, reviewed: true)
        return try XCTUnwrap(H5LaunchProducer(owned: try owned(launch: ownedLaunch), author: try author(launch: authorLaunch), entry: entry))
    }

    private func owned(launch: H5LaunchProducer.EntryLaunch = .absent) throws -> H5LaunchProducer.OwnedLicenseInstall {
        try XCTUnwrap(H5LaunchProducer.OwnedLicenseInstall(
            requestID: ownedID, licenseId: "lic-1", moduleId: "mod-1", purchasedVersionId: "rel-1",
            contentHash: hash, termsHash: terms, status: "ACTIVE", launch: launch))
    }

    private func author(launch: H5LaunchProducer.EntryLaunch = .absent) throws -> H5LaunchProducer.AuthorSubmission {
        try XCTUnwrap(H5LaunchProducer.AuthorSubmission(requestID: authorID, launch: launch))
    }

    private func launch(shell: URL, nonce: String = "nonce1", mainToken: String? = nil) -> H5LaunchProducer.EntryLaunch {
        .init(parentOrigin: origin, nonce: nonce, shellURL: shell, mainToken: mainToken)
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

private final class LaunchInstallRead: WorkshopOriginalInstallReading, @unchecked Sendable {
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
