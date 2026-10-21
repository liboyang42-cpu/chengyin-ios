import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor final class EntryUpgradeDraftFiles: WorkshopUpgradeDraftWriting {
    var values: [String: Data] = [:]
    var failWrite = false
    func read(_ key: String) throws -> Data? { values[key] }
    func writeAtomic(_ key: String, _ data: Data) throws {
        if failWrite { throw WorkshopUpgradeDraftIssue.saveFailed }
        values[key] = data
    }
    func remove(_ key: String) throws { values[key] = nil }
}

@MainActor final class WorkshopUpgradeDraftEntryTests: XCTestCase {
    private func purchased(status: String = "ACTIVE") throws -> WorkshopPurchasedItem {
        let payload: [String: Any] = ["licenseId": "w18-paid-53", "moduleId": "synthetic-module", "purchasedVersionId": "v1-0-0", "contentHash": String(repeating: "a", count: 64), "status": status, "acquiredAt": "2026-10-19T00:00:00Z", "termsVersion": "terms-1", "termsHash": String(repeating: "b", count: 64), "commercialUse": "PROHIBITED", "adaptation": "LOCAL_ADAPTATION", "translation": "PROHIBITED", "updates": "EXACT_PURCHASED_VERSION", "redistribution": "PROHIBITED", "allowedRegions": ["synthetic-region"], "themeLimit": ["unlimited": false, "maximum": 1], "merchantLimit": ["unlimited": false, "maximum": 0], "runLimit": ["unlimited": false, "maximum": 10], "acquisition": "PAID", "buyerKind": "INDIVIDUAL", "useDuration": "PERPETUAL_PURCHASED_VERSION", "contentUseStatus": "PAID_INSTALL_AUTHORITY_UNAVAILABLE", "purchaseActionStatus": "CHANNEL_APPROVAL_REQUIRED"]
        return try JSONDecoder().decode(WorkshopPurchasedItem.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    private func presentation(_ item: WorkshopPurchasedItem) throws -> WorkshopModUpgradePresentation {
        let term = try WorkshopPurchasedUseTerm(item)
        let installed = try WorkshopModVersionRef(moduleId: item.moduleId, versionId: item.purchasedVersionId, packageVersion: "1.0.0", contentHash: item.contentHash, capabilities: ["choice"])
        let candidate = try WorkshopModVersionRef(moduleId: item.moduleId, versionId: "v1-1-0", packageVersion: "1.1.0", contentHash: String(repeating: "c", count: 64), capabilities: ["choice"])
        return WorkshopModUpgradePresentation(term: term, preview: try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered))
    }

    func testVoidSaveFailureDoesNotMarkTheDraftSaved() throws {
        let item = try purchased()
        let preview = try presentation(item)
        let draft = try preview.makeUpgradeDraftRequest(confirmedByBuyer: true, requestId: "upgrade-0001")
        var draftSaved = false
        var showing = true
        let handlers = WorkshopPurchasedUpgradeHandlers(compare: { _ in nil }, saveDraft: { _ in throw WorkshopUpgradeDraftIssue.saveFailed })
        WorkshopPurchasedUpgradeEntry.performSaveDraft(draft, handlers: handlers, draftSaved: &draftSaved, showing: &showing)
        XCTAssertFalse(draftSaved)
        XCTAssertTrue(showing)
        let closed: WorkshopPurchasedUpgradeFactory = { nil }
        XCTAssertNil(closed())
    }

    func testCommitFailureStaysOnTheSheetAndSuccessRestoresWithoutChangingThePurchasedVersion() throws {
        let item = try purchased()
        let preview = try presentation(item)
        let draft = try preview.makeUpgradeDraftRequest(confirmedByBuyer: true, requestId: "upgrade-0001")
        let files = EntryUpgradeDraftFiles()
        files.failWrite = true
        let account = try WorkshopUpgradeAccountLease(accountID: 53, namespace: "player", realm: "local-realm", epoch: 7)
        var failing = WorkshopPurchasedUpgradeHandlers(compare: { _ in preview }, saveDraft: { _ in }, flow: WorkshopUpgradeFlow(store: WorkshopUpgradeDraftStore(writer: files, gate: WorkshopUpgradeAccountGate(account))))
        let token = try failing.flow?.begin(item: item)
        var draftSaved = false
        var showing = true
        var saveFailed = false
        var receipt: WorkshopUpgradeDraftReceipt?
        XCTAssertThrowsError(try WorkshopPurchasedUpgradeEntry.performCommitDraft(draft, handlers: failing, item: item, presentation: preview, token: try XCTUnwrap(token), current: token, draftSaved: &draftSaved, showing: &showing, saveFailed: &saveFailed, receipt: &receipt))
        XCTAssertFalse(draftSaved)
        XCTAssertTrue(showing)
        XCTAssertTrue(saveFailed)
        XCTAssertNil(receipt)
        XCTAssertEqual(item.purchasedVersionId, "v1-0-0")
        files.failWrite = false
        let saved = try WorkshopPurchasedUpgradeEntry.performCommitDraft(draft, handlers: failing, item: item, presentation: preview, token: try XCTUnwrap(token), current: token, draftSaved: &draftSaved, showing: &showing, saveFailed: &saveFailed, receipt: &receipt)
        XCTAssertEqual(saved?.persisted, true)
        XCTAssertTrue(draftSaved)
        XCTAssertFalse(showing)
        XCTAssertFalse(saveFailed)
        XCTAssertEqual(item.contentHash, String(repeating: "a", count: 64))
        var restoredSaved = false
        var restoredReceipt: WorkshopUpgradeDraftReceipt?
        WorkshopPurchasedUpgradeEntry.performRestore(item: item, handlers: failing, draftSaved: &restoredSaved, receipt: &restoredReceipt)
        XCTAssertTrue(restoredSaved)
        XCTAssertEqual(restoredReceipt, saved)
        var staleSaved = false
        var staleShowing = true
        var staleFailed = false
        var staleReceipt: WorkshopUpgradeDraftReceipt?
        XCTAssertThrowsError(try WorkshopPurchasedUpgradeEntry.performCommitDraft(draft, handlers: failing, item: item, presentation: preview, token: UUID(), current: token, draftSaved: &staleSaved, showing: &staleShowing, saveFailed: &staleFailed, receipt: &staleReceipt)) { XCTAssertEqual($0 as? WorkshopUpgradeDraftIssue, .stalePresentation) }
        XCTAssertFalse(staleSaved)
        XCTAssertTrue(staleShowing)
        XCTAssertEqual(files.values.count, 1)
        var current = token
        WorkshopPurchasedUpgradeEntry.performCancel(showing: &showing, compareToken: &current, flow: failing.flow)
        XCTAssertNil(current)
        var checking = true
        var unavailable = false
        var active: WorkshopModUpgradePresentation?
        var opened = false
        WorkshopPurchasedUpgradeEntry.performAcceptCompare(token: UUID(), current: nil, item: item, result: preview, checking: &checking, unavailable: &unavailable, presentation: &active, showing: &opened)
        XCTAssertFalse(opened)
        XCTAssertNil(active)
        XCTAssertTrue(checking)
    }
}
