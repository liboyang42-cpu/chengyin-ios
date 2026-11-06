import XCTest
@testable import QuestifyCore

@MainActor final class MemoryUpgradeDraftFiles: WorkshopUpgradeDraftWriting {
    var values: [String: Data] = [:]
    var failWrite = false
    var corruptRead = false
    var writes = 0
    var removes = 0
    private var reads = 0
    func read(_ key: String) throws -> Data? {
        reads += 1
        guard var data = values[key] else { return nil }
        if corruptRead && reads > 1 { data.append(0x21) }
        return data
    }
    func writeAtomic(_ key: String, _ data: Data) throws {
        writes += 1
        if failWrite { throw WorkshopUpgradeDraftIssue.saveFailed }
        values[key] = data
    }
    func remove(_ key: String) throws { removes += 1; values[key] = nil }
}

@MainActor final class WorkshopUpgradeDraftTests: XCTestCase {
    private func purchased(license: String = "w18-paid-53", module: String = "synthetic-module", version: String = "v1-0-0", hash: Character = "a", status: String = "ACTIVE") throws -> WorkshopPurchasedItem {
        let payload: [String: Any] = ["licenseId": license, "moduleId": module, "purchasedVersionId": version, "contentHash": String(repeating: hash, count: 64), "status": status, "acquiredAt": "2026-10-19T00:00:00Z", "termsVersion": "terms-1", "termsHash": String(repeating: "b", count: 64), "commercialUse": "PROHIBITED", "adaptation": "LOCAL_ADAPTATION", "translation": "PROHIBITED", "updates": "EXACT_PURCHASED_VERSION", "redistribution": "PROHIBITED", "allowedRegions": ["synthetic-region"], "themeLimit": ["unlimited": false, "maximum": 1], "merchantLimit": ["unlimited": false, "maximum": 0], "runLimit": ["unlimited": false, "maximum": 10], "acquisition": "PAID", "buyerKind": "INDIVIDUAL", "useDuration": "PERPETUAL_PURCHASED_VERSION", "contentUseStatus": "PAID_INSTALL_AUTHORITY_UNAVAILABLE", "purchaseActionStatus": "CHANNEL_APPROVAL_REQUIRED"]
        return try JSONDecoder().decode(WorkshopPurchasedItem.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    private func lease(account: Int64 = 53, namespace: String = "player", realm: String = "local-realm", epoch: UInt64 = 7) throws -> WorkshopUpgradeAccountLease {
        try WorkshopUpgradeAccountLease(accountID: account, namespace: namespace, realm: realm, epoch: epoch)
    }
    private func presentation(_ item: WorkshopPurchasedItem, coverage: WorkshopUpgradePreview.Coverage = .covered, version: String = "v1-1-0", semver: String = "1.1.0", hash: Character = "c", caps: Set<String> = ["choice", "geo.arrival"]) throws -> WorkshopModUpgradePresentation {
        let term = try WorkshopPurchasedUseTerm(item)
        let installed = try WorkshopModVersionRef(moduleId: item.moduleId, versionId: item.purchasedVersionId, packageVersion: "1.0.0", contentHash: item.contentHash, capabilities: ["choice"])
        let candidate = try WorkshopModVersionRef(moduleId: item.moduleId, versionId: version, packageVersion: semver, contentHash: String(repeating: hash, count: 64), capabilities: caps)
        return WorkshopModUpgradePresentation(term: term, preview: try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: coverage))
    }
    private func opened(_ item: WorkshopPurchasedItem, files: MemoryUpgradeDraftFiles, account: WorkshopUpgradeAccountLease) throws -> (WorkshopUpgradeFlow, UUID, WorkshopModUpgradePresentation) {
        let flow = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: files, gate: WorkshopUpgradeAccountGate(account)))
        return (flow, try flow.begin(item: item), try presentation(item))
    }

    func testLeaseRejectsEmptyAccountPathAndCredentialMarker() {
        XCTAssertThrowsError(try WorkshopUpgradeAccountLease(accountID: 0, namespace: "player", realm: "local-realm", epoch: 1))
        XCTAssertThrowsError(try WorkshopUpgradeAccountLease(accountID: 1, namespace: "a/b", realm: "local-realm", epoch: 1))
        XCTAssertThrowsError(try WorkshopUpgradeAccountLease(accountID: 1, namespace: "player", realm: "user@host", epoch: 1))
    }

    func testSaveFailureDoesNotReportSuccessOrLeaveADraft() throws {
        let item = try purchased()
        let files = MemoryUpgradeDraftFiles()
        files.failWrite = true
        let (flow, token, preview) = try opened(item, files: files, account: try lease())
        let pinned = (item.purchasedVersionId, item.contentHash)
        XCTAssertThrowsError(try flow.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .saveFailed) }
        XCTAssertTrue(files.values.isEmpty)
        XCTAssertEqual(item.purchasedVersionId, pinned.0)
        XCTAssertEqual(item.contentHash, pinned.1)
        XCTAssertNil(try flow.restore(item: item))
    }

    func testReadbackMismatchRemovesTheFileAndRefusesTheReceipt() throws {
        let item = try purchased()
        let files = MemoryUpgradeDraftFiles()
        files.corruptRead = true
        let (flow, token, preview) = try opened(item, files: files, account: try lease())
        XCTAssertThrowsError(try flow.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .saveFailed) }
        XCTAssertEqual(files.removes, 1)
        XCTAssertTrue(files.values.isEmpty)
    }

    func testAtomicSaveRestoresForTheSameLeaseAndPinsThePurchasedVersion() throws {
        let item = try purchased()
        let account = try lease()
        let files = MemoryUpgradeDraftFiles()
        let (flow, token, preview) = try opened(item, files: files, account: account)
        let pinned = (item.purchasedVersionId, item.contentHash)
        let receipt = try flow.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)
        XCTAssertTrue(receipt.persisted)
        XCTAssertEqual(receipt.addedCapabilities, ["geo.arrival"])
        XCTAssertTrue(receipt.removedCapabilities.isEmpty)
        XCTAssertEqual(receipt.fromVersionId, pinned.0)
        XCTAssertEqual(receipt.fromContentHash, pinned.1)
        XCTAssertEqual(item.purchasedVersionId, pinned.0)
        XCTAssertEqual(item.contentHash, pinned.1)
        let reopened = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: files, gate: WorkshopUpgradeAccountGate(try lease())))
        XCTAssertEqual(try reopened.restore(item: item), receipt)
        XCTAssertEqual(files.values.count, 1)
    }

    func testDirectoryWriteIsOneRegularFileAndReopens() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("upgrade-draft-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try purchased()
        let account = try lease()
        let directory = WorkshopUpgradeDraftDirectory(root: root)
        let flow = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: directory, gate: WorkshopUpgradeAccountGate(account)))
        let token = try flow.begin(item: item)
        let receipt = try flow.commit(item: item, presentation: try presentation(item), confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)
        let names = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertEqual(names.count, 1)
        let again = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: WorkshopUpgradeDraftDirectory(root: root), gate: WorkshopUpgradeAccountGate(try lease())))
        XCTAssertEqual(try again.restore(item: item), receipt)
        let linkRoot = FileManager.default.temporaryDirectory.appendingPathComponent("upgrade-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: linkRoot) }
        try FileManager.default.createDirectory(at: linkRoot, withIntermediateDirectories: true)
        let outside = linkRoot.appendingPathComponent("outside")
        try Data("x".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: linkRoot.appendingPathComponent("abc"), withDestinationURL: outside)
        XCTAssertThrowsError(try WorkshopUpgradeDraftDirectory(root: linkRoot).writeAtomic("abc", Data("nope".utf8))) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .saveFailed) }
    }

    func testDuplicateConfirmDoesNotCreateASecondDraft() throws {
        let item = try purchased()
        let files = MemoryUpgradeDraftFiles()
        let (flow, token, preview) = try opened(item, files: files, account: try lease())
        let first = try flow.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)
        let second = try flow.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0002", generation: token)
        XCTAssertEqual(first.requestId, "upgrade-0001")
        XCTAssertEqual(second, first)
        XCTAssertEqual(files.writes, 1)
        XCTAssertEqual(files.values.count, 1)
    }

    func testConflictCancelAndStaleGenerationDoNotWrite() throws {
        let item = try purchased()
        let files = MemoryUpgradeDraftFiles()
        let (flow, token, preview) = try opened(item, files: files, account: try lease())
        _ = try flow.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)
        let other = try presentation(item, version: "v2-0-0", semver: "2.0.0", hash: "d", caps: ["choice"])
        XCTAssertThrowsError(try flow.commit(item: item, presentation: other, confirmedByBuyer: true, requestId: "upgrade-0003", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .conflict) }
        XCTAssertEqual(files.writes, 1)
        let fresh = MemoryUpgradeDraftFiles()
        let begun = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: fresh, gate: WorkshopUpgradeAccountGate(try lease())))
        let first = try begun.begin(item: item)
        let second = try begun.begin(item: item)
        XCTAssertThrowsError(try begun.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: first)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .stalePresentation) }
        begun.cancel()
        XCTAssertThrowsError(try begun.commit(item: item, presentation: preview, confirmedByBuyer: true, requestId: "upgrade-0001", generation: second)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .stalePresentation) }
        XCTAssertEqual(fresh.writes, 0)
        XCTAssertTrue(fresh.values.isEmpty)
    }

    func testUnknownCoverageRevocationAndNewPurchaseAreRefused() throws {
        let item = try purchased()
        let files = MemoryUpgradeDraftFiles()
        let (flow, token, _) = try opened(item, files: files, account: try lease())
        XCTAssertThrowsError(try flow.commit(item: item, presentation: try presentation(item, coverage: .unknown), confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .licenseUnknown) }
        XCTAssertThrowsError(try flow.commit(item: item, presentation: try presentation(item, coverage: .requiresNewPurchase), confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .notCovered) }
        XCTAssertThrowsError(try flow.commit(item: item, presentation: try presentation(item), confirmedByBuyer: false, requestId: "upgrade-0001", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .unconfirmed) }
        let revoked = try purchased(status: "REVOKED")
        XCTAssertThrowsError(try flow.begin(item: revoked)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .revoked) }
        XCTAssertThrowsError(try flow.commit(item: revoked, presentation: try presentation(item), confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .revoked) }
        XCTAssertEqual(files.writes, 0)
    }

    func testRestoreRejectsRevokedLeaseHashModuleAndVersionMismatches() throws {
        let item = try purchased()
        let account = try lease()
        let gate = WorkshopUpgradeAccountGate(account)
        let files = MemoryUpgradeDraftFiles()
        let flow = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: files, gate: gate))
        let token = try flow.begin(item: item)
        _ = try flow.commit(item: item, presentation: try presentation(item), confirmedByBuyer: true, requestId: "upgrade-0001", generation: token)
        XCTAssertThrowsError(try flow.restore(item: try purchased(status: "REVOKED"))) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .revoked) }
        XCTAssertThrowsError(try flow.restore(item: try purchased(hash: "e"))) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .invalid) }
        XCTAssertThrowsError(try flow.restore(item: try purchased(module: "other-module"))) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .invalid) }
        XCTAssertThrowsError(try flow.restore(item: try purchased(version: "v9-0-0"))) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .invalid) }
        gate.revoke()
        XCTAssertThrowsError(try flow.restore(item: item)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .staleLease) }
        let foreign = MemoryUpgradeDraftFiles()
        foreign.values = files.values
        let other = WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: foreign, gate: WorkshopUpgradeAccountGate(try lease(account: 99))))
        XCTAssertNil(try other.restore(item: item))
        let planted = PlantedUpgradeDraftFiles(data: files.values.values.first)
        XCTAssertThrowsError(try WorkshopUpgradeDraftStore(writer: planted, gate: WorkshopUpgradeAccountGate(try lease(epoch: 8))).load(item: item)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .staleLease) }
    }
}

@MainActor final class PlantedUpgradeDraftFiles: WorkshopUpgradeDraftWriting {
    let data: Data?
    init(data: Data?) { self.data = data }
    func read(_ key: String) throws -> Data? { data }
    func writeAtomic(_ key: String, _ data: Data) throws {}
    func remove(_ key: String) throws {}
}
