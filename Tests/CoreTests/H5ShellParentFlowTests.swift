import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class H5ShellParentFlowTests: XCTestCase {
    private let requestID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let otherID = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"

    func testSameHostPostsTheNonceThenReadsTheOriginalReceipt() async throws {
        let launch = try XCTUnwrap(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce1", mainToken: nil))
        XCTAssertNil(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce1", mainToken: "session-token"))
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var flow = try releasedFlow()
        let request = try XCTUnwrap(flow.open(shellURL: shell, launch: launch))
        XCTAssertTrue(flow.shellLoaded)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "nonce=nonce1")
        XCTAssertFalse((request.httpBody ?? Data()).contains("token".data(using: .utf8)!))
        let source = ParentInstallRead(fact: WorkshopOriginalInstallFact(
            requestID: requestID, state: "INSTALLED_PRIVATE_DRAFT"))
        let identity = try installedIdentity()
        let read = try await flow.readOriginalReceipt(identity: identity, source: source)
        let again = try await flow.readOriginalReceipt(identity: identity, source: source)
        XCTAssertEqual(read, again)
        XCTAssertEqual(again.requestID, requestID)
        XCTAssertEqual(again.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(flow.receipt, again)
        XCTAssertEqual(source.requestIDs, [requestID, requestID])
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(flow.entry.release.journey.machine.phase, .idle)
        XCTAssertThrowsError(try flow.rejectSelfReportClear()) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(flow.entry.release.journey.machine.phase, .idle)
        XCTAssertNotEqual(flow.entry.answers.phase, .matched)
        XCTAssertEqual(flow.receipt, again)
        XCTAssertFalse(flow.clientResultInstalled(["score": "9", "rewardId": "prize"]))
        XCTAssertFalse(flow.clientResultIsServerPass)
        XCTAssertFalse(flow.opensZip)
        XCTAssertEqual(flow.entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(flow.entry.registerPublic(), .publicRegistryReserved)
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
    }

    func testDifferentHostDoesNotLoadOrRead() async throws {
        let launch = try XCTUnwrap(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce1", mainToken: nil))
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var flow = H5ShellParentFlow(requestID: requestID)
        let source = ParentInstallRead(fact: WorkshopOriginalInstallFact(
            requestID: requestID, state: "INSTALLED_PRIVATE_DRAFT"))
        let identity = try installedIdentity()
        XCTAssertNil(flow.open(shellURL: try XCTUnwrap(URL(string: "https://evil.example/shell")), launch: launch))
        XCTAssertNil(flow.open(shellURL: try XCTUnwrap(URL(string: "http://shell.chengyin.test/shell")), launch: launch))
        XCTAssertNil(flow.open(shellURL: try XCTUnwrap(URL(string: "https://user:secret@shell.chengyin.test/shell")), launch: launch))
        XCTAssertNil(flow.open(shellURL: try XCTUnwrap(URL(string: "https://shell.chengyin.test:8443/shell")), launch: launch))
        XCTAssertNil(flow.open(shellURL: nil, launch: launch))
        XCTAssertNil(flow.open(shellURL: shell, launch: nil))
        XCTAssertFalse(flow.shellLoaded)
        do {
            _ = try await flow.readOriginalReceipt(identity: identity, source: source)
            XCTFail("not loaded")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(flow.receipt)
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
        XCTAssertThrowsError(try flow.rejectSelfReportClear()) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
        XCTAssertNil(flow.receipt)
    }

    func testUnreadReleaseDoesNotInventApprovalOrInstall() async throws {
        let launch = try XCTUnwrap(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce1", mainToken: nil))
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        var flow = H5ShellParentFlow(requestID: requestID)
        XCTAssertNotNil(flow.open(shellURL: shell, launch: launch))
        let source = ParentInstallRead(fact: WorkshopOriginalInstallFact(
            requestID: requestID, state: "PREPARED"))
        do {
            _ = try await flow.readOriginalReceipt(identity: try installedIdentity(), source: source)
            XCTFail("approval")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(flow.receipt)
        XCTAssertFalse(flow.entry.release.released)
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
        XCTAssertEqual(flow.entry.openArchive(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(flow.entry.registerPublic(), .publicRegistryReserved)
    }

    func testWrongRequestIsNotRead() async throws {
        let launch = try XCTUnwrap(H5LaunchDescription(
            parentOrigin: "https://shell.chengyin.test", nonce: "nonce1", mainToken: nil))
        let shell = try XCTUnwrap(URL(string: "https://shell.chengyin.test/shell"))
        let prepared = try releasedFlow()
        var flow = H5ShellParentFlow(requestID: otherID, entry: prepared.entry)
        XCTAssertNotNil(flow.open(shellURL: shell, launch: launch))
        let source = ParentInstallRead(fact: WorkshopOriginalInstallFact(
            requestID: requestID, state: "INSTALLED_PRIVATE_DRAFT"))
        do {
            _ = try await flow.readOriginalReceipt(identity: try installedIdentity(), source: source)
            XCTFail("request")
        } catch let error as WorkshopOriginalInstallError {
            XCTAssertEqual(error, .invalidRequest)
        }
        XCTAssertTrue(source.requestIDs.isEmpty)
        XCTAssertNil(flow.receipt)
        XCTAssertEqual(flow.entry.release.journey.machine.installCount, 0)
    }

    private func releasedFlow() throws -> H5ShellParentFlow {
        var entry = WorkshopInstallRecoverEntry()
        let hash = String(repeating: "ab", count: 32)
        try entry.submitManifest(manifest(hash), entry: "mod-1", originalRequestID: requestID)
        try entry.releaseReviewed(termsHash: String(repeating: "cd", count: 32), reviewed: true)
        return H5ShellParentFlow(requestID: requestID, entry: entry)
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

private final class ParentInstallRead: WorkshopOriginalInstallReading, @unchecked Sendable {
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
