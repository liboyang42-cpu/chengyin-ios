import XCTest
@testable import QuestifyCore

final class ReleasePreflightAndUIReadinessContractTests: XCTestCase {
    func testMarketProfileAndSessionRealmRegionalIsolation() {
        XCTAssertEqual(ReleasePreflightAndUIReadinessContract.MarketProfile.parse("cn"), .cn)
        XCTAssertEqual(ReleasePreflightAndUIReadinessContract.MarketProfile.parse(" US "), .us)
        XCTAssertNil(ReleasePreflightAndUIReadinessContract.MarketProfile.parse(""))
        XCTAssertNil(ReleasePreflightAndUIReadinessContract.MarketProfile.parse("EU"))
        XCTAssertNil(ReleasePreflightAndUIReadinessContract.MarketProfile.parse(nil))

        XCTAssertTrue(ReleasePreflightAndUIReadinessContract.MarketProfile.cn.acceptsSessionRealm("cn-prod-01"))
        XCTAssertTrue(ReleasePreflightAndUIReadinessContract.MarketProfile.us.acceptsSessionRealm("us-staging_02"))

        // Cross-market session realm must fail closed.
        XCTAssertFalse(ReleasePreflightAndUIReadinessContract.MarketProfile.cn.acceptsSessionRealm("us-prod-01"))
        XCTAssertFalse(ReleasePreflightAndUIReadinessContract.MarketProfile.us.acceptsSessionRealm("cn-prod-01"))
        XCTAssertFalse(ReleasePreflightAndUIReadinessContract.MarketProfile.cn.acceptsSessionRealm(""))
        XCTAssertFalse(ReleasePreflightAndUIReadinessContract.MarketProfile.cn.acceptsSessionRealm("default"))
        XCTAssertFalse(ReleasePreflightAndUIReadinessContract.MarketProfile.cn.acceptsSessionRealm("cn-invalid/realm"))
    }

    func testSessionAdmissionRoleEvaluationFailsClosed() {
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: "USER"),
            .admitted(.user)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: " player "),
            .admitted(.user)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: "MERCHANT"),
            .admitted(.merchant)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: "CLUB_ADMIN"),
            .admitted(.clubAdmin)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: nil),
            .missingOrEmptyRole
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: "   "),
            .missingOrEmptyRole
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.evaluateSessionAdmission(serverRole: "SUPERUSER"),
            .unrecognizedRole("SUPERUSER")
        )
    }

    func testAPIBaseURLValidationRejectsLegacyMiniProgramHostAndInsecureURLs() {
        let legacyHost = ReleasePreflightAndUIReadinessContract.forbiddenLegacyMiniProgramHost
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("https://\(legacyHost)/api"),
            .failure(.legacyMiniProgramHostRejected)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("http://\(legacyHost):8080"),
            .failure(.legacyMiniProgramHostRejected)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("http://api.cn.questify.example"),
            .failure(.nonHTTPS)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("https://api.cn.questify.example?debug=1"),
            .failure(.containsCredentialsQueryOrFragment)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("https://localhost/api"),
            .failure(.placeholderOrLoopbackHost)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("https://api.questify.invalid"),
            .failure(.placeholderOrLoopbackHost)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("https://192.0.2.10/api"),
            .failure(.placeholderOrLoopbackHost)
        )
        XCTAssertEqual(
            ReleasePreflightAndUIReadinessContract.validateAPIBaseURL(""),
            .failure(.missingOrMalformed)
        )

        let validResult = ReleasePreflightAndUIReadinessContract.validateAPIBaseURL("https://api.cn.questify.example")
        if case .success(let url) = validResult {
            XCTAssertEqual(url.host, "api.cn.questify.example")
        } else {
            XCTFail("Expected valid HTTPS release API base URL to succeed, got \(validResult)")
        }
    }

    func testEndpointAllowlistGatesFailClosedDefaultAndComplianceApproval() {
        let defaultGates = ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates()
        XCTAssertTrue(defaultGates.isFailClosedDefault)
        XCTAssertTrue(defaultGates.unapprovedEnabledGates.isEmpty)

        let unapprovedGates = ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates(
            smsSendEnabled: true,
            paymentAndWithdrawalEnabled: true,
            topicLikeGrantEnabled: true,
            npcChatRemoteDeleteEnabled: true,
            approvedGates: [.smsSend],
            unreviewedWriteRoutes: ["POST /api/unreviewed/mutation"]
        )
        XCTAssertFalse(unapprovedGates.isFailClosedDefault)
        XCTAssertEqual(
            unapprovedGates.unapprovedEnabledGates,
            [.npcChatRemoteDelete, .topicLikeWrite, .paymentAndWithdrawal].sorted()
        )

        let fullyApprovedGates = ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates(
            smsSendEnabled: true,
            wechatSignInEnabled: true,
            approvedGates: [.smsSend, .wechatSignIn]
        )
        XCTAssertTrue(fullyApprovedGates.unapprovedEnabledGates.isEmpty)
    }

    func testSafeUnconfiguredCIDefaultsFailReleasePreflightUntilOverridden() {
        let ciDefaults = ReleasePreflightAndUIReadinessContract.BuildCoordinates.safeBaseDefaults
        XCTAssertTrue(ciDefaults.isSafeUnconfiguredCIDefault)

        let defaultViolations = ReleasePreflightAndUIReadinessContract.verifyReleasePreflight(
            coordinates: ciDefaults,
            serverUserInfoRole: nil
        )
        XCTAssertEqual(
            defaultViolations,
            [
                .codeSigningDisabled,
                .placeholderOrEmptyBundleIdentifier,
                .missingDevelopmentTeam,
                .invalidOrMissingMarket,
                .apiBaseURLViolation(.missingOrMalformed),
                .sessionAdmissionRoleRejected(.missingOrEmptyRole)
            ]
        )

        let releaseCoordinates = ReleasePreflightAndUIReadinessContract.BuildCoordinates(
            codeSigningAllowed: true,
            bundleIdentifier: "cn.questify.ios.release",
            developmentTeam: "TEAM99ABCD",
            rawMarket: "CN",
            rawAPIBaseURL: "https://api.cn.questify.example",
            rawSessionRealm: "cn-release-main"
        )
        XCTAssertFalse(releaseCoordinates.isSafeUnconfiguredCIDefault)

        let releaseViolations = ReleasePreflightAndUIReadinessContract.verifyReleasePreflight(
            coordinates: releaseCoordinates,
            serverUserInfoRole: "MERCHANT",
            gates: .init()
        )
        XCTAssertTrue(releaseViolations.isEmpty, "Expected 0 preflight violations, got \(releaseViolations)")
    }

    func testUIReadinessProjectEditorOffScreenFormRevealContract() {
        let editorContract = UIReadinessAnchorContract.contract(for: .projectEditor)
        XCTAssertEqual(editorContract.rootAccessibilityIdentifier, "projectEditor.form")
        XCTAssertEqual(editorContract.primaryInteractiveAnchorIdentifier, "projectEditor.name")
        XCTAssertTrue(editorContract.requiresOffScreenFormReveal)
        XCTAssertEqual(editorContract.revealHelperIdentifier, "revealProjectEditorNameInForm")

        let partialMount: Set<String> = ["projectEditor.form"]
        XCTAssertEqual(
            editorContract.evaluateReadiness(mountedIdentifiers: partialMount, offScreenRevealed: false),
            .missingAnchors(["projectEditor.name", "projectEditor.reviewReadiness"])
        )

        let fullMountBeforeScroll: Set<String> = [
            "projectEditor.form",
            "projectEditor.name",
            "projectEditor.reviewReadiness"
        ]
        XCTAssertEqual(
            editorContract.evaluateReadiness(mountedIdentifiers: fullMountBeforeScroll, offScreenRevealed: false),
            .awaitingOffScreenReveal(helper: "revealProjectEditorNameInForm", targetAnchor: "projectEditor.name")
        )
        XCTAssertEqual(
            editorContract.evaluateReadiness(mountedIdentifiers: fullMountBeforeScroll, offScreenRevealed: true),
            .ready
        )
    }

    func testAllUIReadinessSurfaceContractsHaveUniqueNonEmptyAnchors() {
        let contracts = UIReadinessAnchorContract.allContracts
        XCTAssertEqual(contracts.count, UIReadinessFlowSurface.allCases.count)

        var seenRoots: Set<String> = []
        var seenPrimaries: Set<String> = []
        for contract in contracts {
            XCTAssertFalse(contract.rootAccessibilityIdentifier.isEmpty)
            XCTAssertFalse(contract.primaryInteractiveAnchorIdentifier.isEmpty)
            XCTAssertTrue(contract.requiredAnchorIdentifiers.contains(contract.rootAccessibilityIdentifier))
            XCTAssertTrue(contract.requiredAnchorIdentifiers.contains(contract.primaryInteractiveAnchorIdentifier))
            XCTAssertTrue(seenRoots.insert(contract.rootAccessibilityIdentifier).inserted)
            XCTAssertTrue(seenPrimaries.insert(contract.primaryInteractiveAnchorIdentifier).inserted)

            let mounted = Set(contract.requiredAnchorIdentifiers)
            XCTAssertEqual(
                contract.evaluateReadiness(mountedIdentifiers: mounted, offScreenRevealed: true),
                .ready
            )
        }
    }
}
