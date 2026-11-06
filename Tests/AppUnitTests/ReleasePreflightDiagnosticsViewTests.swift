import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor final class ReleasePreflightDiagnosticsViewTests: XCTestCase {
    func testSafeCIDefaultPostureAndViewInstantiation() {
        let view = ReleasePreflightDiagnosticsView()
        let report = view.report

        XCTAssertEqual(report, .ciDefault)
        XCTAssertTrue(report.isSafeUnconfiguredCIDefault)
        XCTAssertFalse(report.coordinates.codeSigningAllowed)
        XCTAssertEqual(
            report.coordinates.bundleIdentifier,
            ReleasePreflightAndUIReadinessContract.placeholderBundleIdentifier
        )
        XCTAssertTrue(report.gates.isFailClosedDefault)
        XCTAssertFalse(report.isReadyForReleaseArchive)
        XCTAssertTrue(report.violations.contains(.codeSigningDisabled))
        XCTAssertTrue(report.violations.contains(.placeholderOrEmptyBundleIdentifier))
        XCTAssertEqual(report.sessionAdmission, .missingOrEmptyRole)
        XCTAssertEqual(view.anchorContracts.count, 5)
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeViolation(.codeSigningDisabled),
            "代码签名未开启 (CODE_SIGNING_ALLOWED=NO)"
        )
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeSessionAdmission(report.sessionAdmission),
            "阻断：缺少服务端 role 字段 (Fail-Closed)"
        )
        _ = view.body
    }

    func testValidCNAndUSArchiveConfigurationsPassPreflight() {
        let cnCoordinates = ReleasePreflightAndUIReadinessContract.BuildCoordinates(
            codeSigningAllowed: true,
            bundleIdentifier: "com.chengyin.questify.cn",
            developmentTeam: "A1B2C3D4E5",
            rawMarket: "CN",
            rawAPIBaseURL: "https://api.chengyin.cn",
            rawSessionRealm: "cn-prod-v1"
        )
        let cnView = ReleasePreflightDiagnosticsView(
            coordinates: cnCoordinates,
            serverUserInfoRole: "USER"
        )
        XCTAssertTrue(cnView.report.isReadyForReleaseArchive)
        XCTAssertTrue(cnView.report.violations.isEmpty)
        XCTAssertFalse(cnView.report.isSafeUnconfiguredCIDefault)
        XCTAssertEqual(cnView.report.sessionAdmission, .admitted(.user))
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeSessionAdmission(cnView.report.sessionAdmission),
            "已准入 (USER)"
        )
        _ = cnView.body

        let usCoordinates = ReleasePreflightAndUIReadinessContract.BuildCoordinates(
            codeSigningAllowed: true,
            bundleIdentifier: "com.chengyin.questify.us",
            developmentTeam: "A1B2C3D4E5",
            rawMarket: "US",
            rawAPIBaseURL: "https://api.questify.us",
            rawSessionRealm: "us-prod-v1"
        )
        let usGates = ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates(
            appleSignInEnabled: true,
            approvedGates: [.appleSignIn]
        )
        let usView = ReleasePreflightDiagnosticsView(
            coordinates: usCoordinates,
            serverUserInfoRole: "MERCHANT",
            gates: usGates
        )
        XCTAssertTrue(usView.report.isReadyForReleaseArchive)
        XCTAssertTrue(usView.report.violations.isEmpty)
        XCTAssertEqual(usView.report.sessionAdmission, .admitted(.merchant))
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeGateState(enabled: true, approved: true),
            "ON (已审批)"
        )
        _ = usView.body
    }

    func testLegacyMiniProgramHostRejectionAndCrossMarketRealmMismatchDetection() {
        let invalidCoordinates = ReleasePreflightAndUIReadinessContract.BuildCoordinates(
            codeSigningAllowed: true,
            bundleIdentifier: "com.chengyin.questify.cn",
            developmentTeam: "A1B2C3D4E5",
            rawMarket: "CN",
            rawAPIBaseURL: "https://47.103.124.64/api",
            rawSessionRealm: "us-prod-v1"
        )
        let unapprovedGates = ReleasePreflightAndUIReadinessContract.EndpointAllowlistGates(
            smsSendEnabled: true,
            approvedGates: [],
            unreviewedWriteRoutes: ["api/team/report"]
        )
        let view = ReleasePreflightDiagnosticsView(
            coordinates: invalidCoordinates,
            serverUserInfoRole: "UNKNOWN_ROLE",
            gates: unapprovedGates
        )
        let violations = view.report.violations

        XCTAssertFalse(view.report.isReadyForReleaseArchive)
        XCTAssertTrue(violations.contains(.apiBaseURLViolation(.legacyMiniProgramHostRejected)))
        XCTAssertTrue(violations.contains(.crossMarketOrInvalidSessionRealm))
        XCTAssertTrue(violations.contains(.sessionAdmissionRoleRejected(.unrecognizedRole("UNKNOWN_ROLE"))))
        XCTAssertTrue(violations.contains(.unapprovedHighRiskGates([.smsSend])))
        XCTAssertTrue(violations.contains(.unreviewedWriteRoutesPresent(["api/team/report"])))

        XCTAssertTrue(
            ReleasePreflightDiagnosticsView.describeViolation(
                .apiBaseURLViolation(.legacyMiniProgramHostRejected)
            ).contains("47.103.124.64")
        )
        XCTAssertTrue(
            ReleasePreflightDiagnosticsView.describeViolation(
                .crossMarketOrInvalidSessionRealm
            ).contains("QUESTIFY_SESSION_REALM")
        )
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeGateState(enabled: true, approved: false),
            "ON (未审批阻断)"
        )
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeGateState(enabled: false, approved: false),
            "OFF (默认关闭)"
        )
        _ = view.body
    }

    func testUIReadinessAnchorContractsAndOffScreenRevealEvaluation() {
        let allSurfaces = UIReadinessFlowSurface.allCases
        XCTAssertEqual(
            allSurfaces,
            [.projectEditor, .profileSelfEdit, .roamFinishedHistory, .couponRuntimeJourney, .mapCoreEntry]
        )

        let surfaceTitles = allSurfaces.map(ReleasePreflightDiagnosticsView.describeSurfaceTitle)
        XCTAssertEqual(Set(surfaceTitles).count, allSurfaces.count)

        let projectContract = UIReadinessAnchorContract.contract(for: .projectEditor)
        XCTAssertTrue(projectContract.requiresOffScreenFormReveal)
        XCTAssertEqual(projectContract.revealHelperIdentifier, "revealProjectEditorNameInForm")

        let projectMounted = Set(projectContract.requiredAnchorIdentifiers)
        let unrevealedEval = projectContract.evaluateReadiness(
            mountedIdentifiers: projectMounted,
            offScreenRevealed: false
        )
        XCTAssertEqual(
            unrevealedEval,
            .awaitingOffScreenReveal(
                helper: "revealProjectEditorNameInForm",
                targetAnchor: "projectEditor.name"
            )
        )
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeReadinessBadge(unrevealedEval),
            "待滚动显露"
        )
        XCTAssertTrue(
            ReleasePreflightDiagnosticsView.describeReadinessDetail(unrevealedEval)
                .contains("revealProjectEditorNameInForm")
        )

        let revealedEval = projectContract.evaluateReadiness(
            mountedIdentifiers: projectMounted,
            offScreenRevealed: true
        )
        XCTAssertEqual(revealedEval, .ready)
        XCTAssertEqual(
            ReleasePreflightDiagnosticsView.describeReadinessBadge(revealedEval),
            "已就绪 (READY)"
        )

        for surface in [
            UIReadinessFlowSurface.profileSelfEdit,
            .roamFinishedHistory,
            .couponRuntimeJourney,
            .mapCoreEntry
        ] {
            let contract = UIReadinessAnchorContract.contract(for: surface)
            XCTAssertFalse(contract.requiresOffScreenFormReveal)
            let missingEval = contract.evaluateReadiness(mountedIdentifiers: [], offScreenRevealed: false)
            XCTAssertEqual(missingEval, .missingAnchors(contract.requiredAnchorIdentifiers))
            XCTAssertEqual(
                ReleasePreflightDiagnosticsView.describeReadinessBadge(missingEval),
                "待挂载 (\(contract.requiredAnchorIdentifiers.count))"
            )
            let readyEval = contract.evaluateReadiness(
                mountedIdentifiers: Set(contract.requiredAnchorIdentifiers),
                offScreenRevealed: false
            )
            XCTAssertEqual(readyEval, .ready)
        }

        let allRequiredAnchors = Set(UIReadinessAnchorContract.allContracts.flatMap(\.requiredAnchorIdentifiers))
        let readyView = ReleasePreflightDiagnosticsView(
            mountedAnchorIdentifiers: allRequiredAnchors,
            offScreenRevealedSurfaces: [.projectEditor]
        )
        XCTAssertEqual(readyView.mountedAnchorIdentifiers, allRequiredAnchors)
        XCTAssertEqual(readyView.offScreenRevealedSurfaces, [.projectEditor])
        _ = readyView.body
    }
}
