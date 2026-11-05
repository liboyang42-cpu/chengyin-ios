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
        let presentation = WorkshopModUpgradePresentation(term: term, preview: preview, locale: Locale(identifier: "zh-Hans"))

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
        let presentation = WorkshopModUpgradePresentation(term: term, preview: preview, locale: Locale(identifier: "zh-Hans"))

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
        let coveredPresentation = WorkshopModUpgradePresentation(term: term, preview: coveredPreview, locale: Locale(identifier: "zh-Hans"))

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
        let unpurchasedPresentation = WorkshopModUpgradePresentation(term: term, preview: unpurchasedPreview, locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(unpurchasedPresentation.canConfirmUpgrade(confirmedByBuyer: true))
        XCTAssertTrue(unpurchasedPresentation.coverageNotice.contains("另行购买"))

        let unknownPreview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .unknown)
        let unknownPresentation = WorkshopModUpgradePresentation(term: term, preview: unknownPreview, locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(unknownPresentation.canConfirmUpgrade(confirmedByBuyer: true))
    }

    func testPerpetualPurchasedUseDisclosureSurvivesSubscriptionAndForbidsRedistribution() throws {
        XCTAssertThrowsError(try makePurchasedItem(licenseId: "lic-99")) {
            XCTAssertEqual($0 as? WorkshopPurchasedIssue, .malformed)
        }
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem(licenseId: "w18-paid-99", moduleId: "mod-city", versionId: "ver-1"))
        let disclosure = WorkshopPurchasedUseTermPresentation(term: term, locale: Locale(identifier: "zh-Hans"))

        XCTAssertTrue(disclosure.term.survivesSubscriptionEnd)
        XCTAssertFalse(disclosure.term.permitsRedistribution)
        XCTAssertTrue(disclosure.versionSummaryText.contains("w18-paid-99"))
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

        let notice = QmodManifestIssueNotice(issue: issue, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(notice.isH5DesignOnlyRejection)
        XCTAssertTrue(notice.titleText.contains("H5"))
        XCTAssertTrue(notice.bodyText.contains("questify.h5"))

        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(versionId: "v1-0-0", semver: "1.0.0", hashChar: "a", capabilities: ["choice"])
        let candidate = try makeVersion(versionId: "v1-1-0", semver: "1.1.0", hashChar: "b", capabilities: ["choice"])
        let preview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered)
        let blockedPresentation = WorkshopModUpgradePresentation(term: term, preview: preview, manifestIssue: issue, locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(blockedPresentation.canConfirmUpgrade(confirmedByBuyer: true))
    }

    func testManifestAuthorityFieldAndProposalProfileNotices() {
        let authorityNotice = QmodManifestIssueNotice(issue: .authorityField("rewardBudget"), locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(authorityNotice.isH5DesignOnlyRejection)
        XCTAssertTrue(authorityNotice.bodyText.contains("rewardBudget"))

        let proposalText = QmodManifestIssueNotice.proposalProfileNotice(for: .reviewProposalV1, locale: Locale(identifier: "zh-Hans"))
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
        XCTAssertNil(QmodManifestIssueNotice.proposalProfileNotice(for: confirmedProfile, locale: Locale(identifier: "zh-Hans")))
    }
    func testEnglishAndChineseKeepExactUpgradeAuthorizationAndRequest() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(versionId: "v1-0-0", semver: "1.0.0", hashChar: "a", capabilities: ["choice"])
        let candidate = try makeVersion(versionId: "v1-1-0", semver: "1.1.0", hashChar: "b", capabilities: ["choice", "qr.scan"])
        let preview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered)
        let en = WorkshopModUpgradePresentation(term: term, preview: preview, locale: Locale(identifier: "en-US"))
        let zh = WorkshopModUpgradePresentation(term: term, preview: preview, locale: Locale(identifier: "zh-Hans-CN"))
        XCTAssertTrue(en.coverageNotice.contains("license")); XCTAssertTrue(zh.coverageNotice.contains("授权"))
        XCTAssertTrue(en.reReviewRequirementNotice.contains("review again"))
        XCTAssertTrue(en.pinnedExistingRunsNotice.contains("original version (1.0.0)"))
        XCTAssertTrue(en.confirmationPromptText.contains("must be reviewed again"))
        XCTAssertEqual(en.preview, zh.preview); XCTAssertEqual(en.addedCapabilities, zh.addedCapabilities)
        XCTAssertFalse(en.canConfirmUpgrade(confirmedByBuyer: false)); XCTAssertFalse(zh.canConfirmUpgrade(confirmedByBuyer: false))
        XCTAssertEqual(try en.makeUpgradeDraftRequest(confirmedByBuyer: true, requestId: "same-original"),
                       try zh.makeUpgradeDraftRequest(confirmedByBuyer: true, requestId: "same-original"))
        let english = [en.coverageNotice, en.versionTransitionText, en.confirmationPromptText,
                       en.useTermPresentation.subscriptionSurvivalNotice, en.useTermPresentation.redistributionNotice].joined()
        XCTAssertNil(english.range(of: "\\p{Han}", options: .regularExpression))
    }
    func testLanguageCannotOpenUncoveredUnknownOrMismatchedUpgrade() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(versionId: "v1-0-0", semver: "1.0.0", hashChar: "a", capabilities: ["choice"])
        let candidate = try makeVersion(versionId: "v2-0-0", semver: "2.0.0", hashChar: "b", capabilities: ["choice"])
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
            for coverage in [WorkshopUpgradePreview.Coverage.requiresNewPurchase, .unknown] {
                let preview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: coverage)
                let value = WorkshopModUpgradePresentation(term: term, preview: preview, locale: locale)
                XCTAssertFalse(value.canConfirmUpgrade(confirmedByBuyer: true))
                XCTAssertThrowsError(try value.makeUpgradeDraftRequest(confirmedByBuyer: true))
            }
            let mismatched = try WorkshopPurchasedUseTerm(makePurchasedItem(moduleId: "other-module"))
            let preview = try WorkshopUpgradePreview(installed: installed, candidate: candidate, coverage: .covered)
            let value = WorkshopModUpgradePresentation(term: mismatched, preview: preview, locale: locale)
            XCTAssertFalse(value.isTermAlignedWithPreview); XCTAssertFalse(value.canConfirmUpgrade(confirmedByBuyer: true))
        }
    }
    func testEnglishPerpetualTermsKeepSubscriptionAndRedistributionRestrictions() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let value = WorkshopPurchasedUseTermPresentation(term: term, locale: Locale(identifier: "en"))
        XCTAssertTrue(value.subscriptionSurvivalNotice.contains("after your membership or subscription ends"))
        XCTAssertTrue(value.redistributionNotice.contains("Resale, sublicensing and redistribution are prohibited"))
        XCTAssertTrue(value.versionSummaryText.contains(term.licenseId))
        XCTAssertEqual(value.term, term)
        let fallback = WorkshopPurchasedUseTermPresentation(term: term, locale: Locale(identifier: "fr-FR"))
        XCTAssertEqual(fallback.titleText, value.titleText)
    }
    func testAllManifestMessagesHaveBothLanguagesAndPreserveBlockingFacts() {
        let issues: [QmodManifestIssue] = [.h5DesignOnly, .authorityField("budget%field"), .unsupportedFormat,
            .fileTooLarge("image%20.png", actual: 120, limit: 100), .tooManyFiles(actual: 3, limit: 2),
            .expandedTooLarge(actual: 300, limit: 200), .malformed, .invalidPackage, .invalidVersion,
            .invalidEntrypoint, .invalidLocale, .invalidDependency, .unsafePath("../x"), .duplicatePath("x"),
            .missingFile("x"), .digestMismatch("x")]
        for issue in issues {
            let en = QmodManifestIssueNotice(issue: issue, locale: Locale(identifier: "en"))
            let zh = QmodManifestIssueNotice(issue: issue, locale: Locale(identifier: "zh-Hans"))
            XCTAssertEqual(en.issue, zh.issue); XCTAssertEqual(en.isH5DesignOnlyRejection, zh.isH5DesignOnlyRejection)
            XCTAssertFalse(en.titleText.isEmpty); XCTAssertFalse(en.bodyText.isEmpty)
            XCTAssertNotEqual(en.titleText, zh.titleText)
            XCTAssertNil((en.titleText + en.bodyText).range(of: "\\p{Han}", options: .regularExpression))
        }
        let file = QmodManifestIssueNotice(issue: .fileTooLarge("image%20.png", actual: 120, limit: 100), locale: Locale(identifier: "en"))
        XCTAssertTrue(file.bodyText.contains("image%20.png")); XCTAssertTrue(file.bodyText.contains("120 B")); XCTAssertTrue(file.bodyText.contains("100 B"))
        let h5 = QmodManifestIssueNotice(issue: .h5DesignOnly, locale: Locale(identifier: "en"))
        XCTAssertTrue(h5.bodyText.contains("will not load")); XCTAssertTrue(h5.isH5DesignOnlyRejection)
        let proposal = QmodManifestIssueNotice.proposalProfileNotice(for: .reviewProposalV1, locale: Locale(identifier: "en"))
        XCTAssertTrue(proposal?.contains("not the final limits") == true)
    }

}
