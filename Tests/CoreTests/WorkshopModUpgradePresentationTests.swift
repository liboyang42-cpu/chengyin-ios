import XCTest
@testable import QuestifyCore

final class WorkshopModUpgradePresentationTests: XCTestCase {
    private func makePurchasedItem(
        licenseId: String = "w18-paid-29",
        moduleId: String = "synthetic-module",
        versionId: String = "v1-0-0",
        status: String = "ACTIVE"
    ) throws -> WorkshopPurchasedItem {
        let payload: [String: Any] = [
            "licenseId": licenseId,
            "moduleId": moduleId,
            "purchasedVersionId": versionId,
            "contentHash": String(repeating: "a", count: 64),
            "status": status,
            "acquiredAt": "2026-10-19T00:00:00Z",
            "termsVersion": "terms-1",
            "termsHash": String(repeating: "b", count: 64),
            "commercialUse": "PROHIBITED",
            "adaptation": "LOCAL_ADAPTATION",
            "translation": "PROHIBITED",
            "updates": "EXACT_PURCHASED_VERSION",
            "redistribution": "PROHIBITED",
            "allowedRegions": ["synthetic-region"],
            "themeLimit": ["unlimited": false, "maximum": 1],
            "merchantLimit": ["unlimited": false, "maximum": 0],
            "runLimit": ["unlimited": false, "maximum": 10],
            "acquisition": "PAID",
            "buyerKind": "INDIVIDUAL",
            "useDuration": "PERPETUAL_PURCHASED_VERSION",
            "contentUseStatus": "PAID_INSTALL_AUTHORITY_UNAVAILABLE",
            "purchaseActionStatus": "CHANNEL_APPROVAL_REQUIRED"
        ]
        return try JSONDecoder().decode(
            WorkshopPurchasedItem.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private func makeVersion(
        moduleId: String = "synthetic-module",
        versionId: String,
        semver: String,
        hashChar: Character,
        capabilities: Set<String>
    ) throws -> WorkshopModVersionRef {
        try WorkshopModVersionRef(
            moduleId: moduleId,
            versionId: versionId,
            packageVersion: semver,
            contentHash: String(repeating: hashChar, count: 64),
            capabilities: capabilities
        )
    }

    func testCapabilityDiffSortsAddedRemovedAndUnchangedCapabilities() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(
            versionId: "v1-0-0",
            semver: "1.0.0",
            hashChar: "a",
            capabilities: ["choice", "qr.scan", "audio.cue"]
        )
        let candidate = try makeVersion(
            versionId: "v1-2-0",
            semver: "1.2.0",
            hashChar: "c",
            capabilities: ["choice", "geo.arrival", "camera.capture"]
        )
        let preview = try WorkshopUpgradePreview(
            installed: installed,
            candidate: candidate,
            coverage: .covered
        )
        let presentation = WorkshopModUpgradePresentation(term: term, preview: preview)

        XCTAssertTrue(presentation.hasCapabilityChanges)
        XCTAssertEqual(presentation.addedCapabilities, ["camera.capture", "geo.arrival"])
        XCTAssertEqual(presentation.removedCapabilities, ["audio.cue", "qr.scan"])
        XCTAssertEqual(presentation.unchangedCapabilities, ["choice"])
        XCTAssertTrue(presentation.versionTransitionText.contains("1.0.0"))
        XCTAssertTrue(presentation.versionTransitionText.contains("1.2.0"))
    }

    func testPinnedRunsAndReReviewNoticesAlwaysPresent() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(versionId: "v1-0-0", semver: "1.0.0", hashChar: "a", capabilities: ["choice"])
        let candidate = try makeVersion(versionId: "v1-0-1", semver: "1.0.1", hashChar: "b", capabilities: ["choice"])
        let preview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered)
        let presentation = WorkshopModUpgradePresentation(term: term, preview: preview)

        XCTAssertFalse(presentation.hasCapabilityChanges)
        XCTAssertTrue(presentation.preview.pinsExistingRuns)
        XCTAssertTrue(presentation.preview.requiresReview)
        XCTAssertTrue(presentation.pinnedExistingRunsNotice.contains("固定保持原版本"))
        XCTAssertTrue(presentation.reReviewRequirementNotice.contains("重新通过审核"))
    }

    func testBuyerConfirmationGateRequiresCoveredLicenseAndExplicitConfirmation() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(versionId: "v1-0-0", semver: "1.0.0", hashChar: "a", capabilities: ["choice"])
        let candidate = try makeVersion(versionId: "v2-0-0", semver: "2.0.0", hashChar: "d", capabilities: ["choice", "geo.arrival"])

        let coveredPreview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered)
        let coveredPresentation = WorkshopModUpgradePresentation(term: term, preview: coveredPreview)

        XCTAssertFalse(coveredPresentation.canConfirmUpgrade(confirmedByBuyer: false))
        XCTAssertTrue(coveredPresentation.canConfirmUpgrade(confirmedByBuyer: true))
        XCTAssertThrowsError(try coveredPresentation.makeUpgradeDraftRequest(confirmedByBuyer: false)) { error in
            XCTAssertEqual(error as? WorkshopUpgradeIssue, .unconfirmed)
        }

        let request = try coveredPresentation.makeUpgradeDraftRequest(confirmedByBuyer: true, requestId: "req-w18-0001")
        XCTAssertEqual(request.licenseId, "w18-paid-29")
        XCTAssertEqual(request.fromVersionId, "v1-0-0")
        XCTAssertEqual(request.toVersionId, "v2-0-0")
        XCTAssertEqual(request.requestId, "req-w18-0001")

        let unpurchasedPreview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .requiresNewPurchase)
        let unpurchasedPresentation = WorkshopModUpgradePresentation(term: term, preview: unpurchasedPreview)
        XCTAssertFalse(unpurchasedPresentation.canConfirmUpgrade(confirmedByBuyer: true))
        XCTAssertTrue(unpurchasedPresentation.coverageNotice.contains("另行购买"))

        let unknownPreview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .unknown)
        let unknownPresentation = WorkshopModUpgradePresentation(term: term, preview: unknownPreview)
        XCTAssertFalse(unknownPresentation.canConfirmUpgrade(confirmedByBuyer: true))
    }

    func testPerpetualPurchasedUseDisclosureSurvivesSubscriptionAndForbidsRedistribution() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem(licenseId: "lic-99", moduleId: "mod-city", versionId: "ver-1"))
        let disclosure = WorkshopPurchasedUseTermPresentation(term: term)

        XCTAssertTrue(disclosure.term.survivesSubscriptionEnd)
        XCTAssertFalse(disclosure.term.permitsRedistribution)
        XCTAssertTrue(disclosure.versionSummaryText.contains("lic-99"))
        XCTAssertTrue(disclosure.versionSummaryText.contains("mod-city"))
        XCTAssertTrue(disclosure.versionSummaryText.contains("ver-1"))
        XCTAssertTrue(disclosure.subscriptionSurvivalNotice.contains("不随会员或订阅到期而失效"))
        XCTAssertTrue(disclosure.redistributionNotice.contains("严禁转售"))
    }

    func testH5DesignOnlyManifestRejectionNoticeIsExplicit() throws {
        let h5JSON = Data(#"""
        {
          "formatVersion": "1.0",
          "kind": "questify.h5",
          "packageId": "demo.h5",
          "packageVersion": "1.0.0",
          "entrypoint": "content.json",
          "locales": ["zh-Hans"],
          "runtime": {"minHostVersion": "1.0.0", "capabilities": ["choice"]},
          "files": [
            {"path": "content.json", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bytes": 12},
            {"path": "zh-Hans.json", "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "bytes": 12}
          ],
          "rightsDeclaration": {"declared": true},
          "monetizationDeclaration": "NONE"
        }
        """#.utf8)

        var caughtIssue: QmodManifestIssue?
        XCTAssertThrowsError(try QmodManifest(data: h5JSON, limits: .reviewProposalV1)) { error in
            caughtIssue = error as? QmodManifestIssue
        }
        let issue = try XCTUnwrap(caughtIssue)
        XCTAssertEqual(issue, .h5DesignOnly)

        let notice = QmodManifestIssueNotice(issue: issue)
        XCTAssertTrue(notice.isH5DesignOnlyRejection)
        XCTAssertTrue(notice.titleText.contains("H5"))
        XCTAssertTrue(notice.bodyText.contains("questify.h5"))

        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(versionId: "v1-0-0", semver: "1.0.0", hashChar: "a", capabilities: ["choice"])
        let candidate = try makeVersion(versionId: "v1-1-0", semver: "1.1.0", hashChar: "b", capabilities: ["choice"])
        let preview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered)
        let blockedPresentation = WorkshopModUpgradePresentation(term: term, preview: preview, manifestIssue: issue)
        XCTAssertFalse(blockedPresentation.canConfirmUpgrade(confirmedByBuyer: true))
    }

    func testManifestAuthorityFieldAndProposalProfileNotices() {
        let authorityNotice = QmodManifestIssueNotice(issue: .authorityField("rewardBudget"))
        XCTAssertFalse(authorityNotice.isH5DesignOnlyRejection)
        XCTAssertTrue(authorityNotice.bodyText.contains("rewardBudget"))

        let proposalText = QmodManifestIssueNotice.proposalProfileNotice(for: .reviewProposalV1)
        XCTAssertNotNil(proposalText)
        XCTAssertEqual(proposalText?.contains("proposal-v1"), true)

        let confirmedProfile = QmodLimitProfile(
            profileVersion: "server-v1",
            isProposal: false,
            maxArchiveBytes: 25 << 20,
            maxExpandedBytes: 100 << 20,
            maxFileBytes: 20 << 20,
            maxFiles: 2_000,
            maxPathLength: 200,
            maxDepth: 8
        )
        XCTAssertNil(QmodManifestIssueNotice.proposalProfileNotice(for: confirmedProfile))
    }
}
