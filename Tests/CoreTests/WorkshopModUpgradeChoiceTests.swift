import XCTest
@testable import QuestifyCore

final class WorkshopModUpgradeChoiceTests: XCTestCase {
    private func purchased(status: String = "ACTIVE") throws -> WorkshopPurchasedItem {
        var item: [String: Any] = ["licenseId": "w18-paid-11", "moduleId": "synthetic-module", "purchasedVersionId": "synthetic-version", "contentHash": String(repeating: "a", count: 64), "status": status, "acquiredAt": "2026-10-05T00:00:00Z", "termsVersion": "terms-1", "termsHash": String(repeating: "b", count: 64), "commercialUse": "PROHIBITED", "adaptation": "LOCAL_ADAPTATION", "translation": "PROHIBITED", "updates": "EXACT_PURCHASED_VERSION", "redistribution": "PROHIBITED", "allowedRegions": ["synthetic-region"], "themeLimit": ["unlimited": false, "maximum": 1], "merchantLimit": ["unlimited": false, "maximum": 0], "runLimit": ["unlimited": false, "maximum": 10], "acquisition": "PAID", "buyerKind": "INDIVIDUAL", "useDuration": "PERPETUAL_PURCHASED_VERSION", "contentUseStatus": "PAID_INSTALL_AUTHORITY_UNAVAILABLE", "purchaseActionStatus": "CHANNEL_APPROVAL_REQUIRED"]
        item["status"] = status
        return try JSONDecoder().decode(WorkshopPurchasedItem.self, from: JSONSerialization.data(withJSONObject: item))
    }
    private func version(_ id: String, _ semver: String, hash: Character, caps: Set<String> = ["choice"]) throws -> WorkshopModVersionRef {
        try WorkshopModVersionRef(moduleId: "synthetic-module", versionId: id, packageVersion: semver, contentHash: String(repeating: hash, count: 64), capabilities: caps)
    }

    func testPurchasedUseIsPersistentAndNotRedistributable() throws {
        let term = try WorkshopPurchasedUseTerm(purchased())
        XCTAssertTrue(term.survivesSubscriptionEnd); XCTAssertFalse(term.permitsRedistribution)
        XCTAssertThrowsError(try WorkshopPurchasedUseTerm(purchased(status: "REVOKED")))
    }

    func testPreviewDiffsCapabilitiesAndPinsRuns() throws {
        let preview = try WorkshopUpgradePreview(installed: version("synthetic-version", "1.0.0", hash: "a"), candidate: version("v2", "1.1.0", hash: "c", caps: ["choice", "geo.arrival"]), coverage: .covered)
        XCTAssertEqual(preview.addedCapabilities, ["geo.arrival"]); XCTAssertTrue(preview.removedCapabilities.isEmpty)
        XCTAssertTrue(preview.pinsExistingRuns); XCTAssertTrue(preview.requiresReview)
        XCTAssertThrowsError(try WorkshopUpgradePreview(installed: version("synthetic-version", "1.1.0", hash: "a"), candidate: version("v0", "1.0.9", hash: "c"), coverage: .covered)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .notNewer) }
        XCTAssertThrowsError(try WorkshopUpgradePreview(installed: version("synthetic-version", "1.0.0", hash: "a"), candidate: version("synthetic-version", "1.0.0", hash: "a"), coverage: .covered)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .sameVersion) }
    }

    func testUpgradeDraftNeedsExplicitConfirmationAndKnownCoverage() throws {
        let term = try WorkshopPurchasedUseTerm(purchased())
        let installed = try version("synthetic-version", "1.0.0", hash: "a"), candidate = try version("v2", "2.0.0", hash: "c")
        XCTAssertThrowsError(try WorkshopUpgradeDraftRequest(term: term, preview: WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered), confirmedByBuyer: false)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .unconfirmed) }
        XCTAssertThrowsError(try WorkshopUpgradeDraftRequest(term: term, preview: WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .unknown), confirmedByBuyer: true)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .licenseUnknown) }
        XCTAssertThrowsError(try WorkshopUpgradeDraftRequest(term: term, preview: WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .requiresNewPurchase), confirmedByBuyer: true)) { XCTAssertEqual($0 as? WorkshopUpgradeIssue, .notCovered) }
        let request = try WorkshopUpgradeDraftRequest(term: term, preview: WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered), confirmedByBuyer: true, requestId: "upgrade-0001")
        XCTAssertEqual(request.fromVersionId, "synthetic-version"); XCTAssertEqual(request.toVersionId, "v2")
    }
}
