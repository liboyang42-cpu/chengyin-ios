import XCTest
@testable import QuestifyCore

final class ReleaseArchiveAndTestFlightChecklistContractTests: XCTestCase {
    func testUnconfiguredBaseXCConfigIsRejectedWithExpectedBlockerCodes() {
        let result = ReleaseArchiveAndTestFlightChecklistContract.evaluateChecklist(
            xcconfig: .unconfiguredBase
        )

        XCTAssertEqual(result.status, .blocked)
        XCTAssertFalse(result.isReadyForArchive)
        XCTAssertTrue(result.blockerCodes.contains(.codeSigningNotAllowed))
        XCTAssertTrue(result.blockerCodes.contains(.missingOrPlaceholderDevelopmentTeam))
        XCTAssertTrue(result.blockerCodes.contains(.placeholderOrInvalidBundleIdentifier))
        XCTAssertTrue(result.blockerCodes.contains(.missingOrNonHTTPSAPIBaseURL))
        XCTAssertTrue(result.blockerCodes.contains(.missingOrMismatchedSessionRealm))
    }

    func testValidCNAndUSArchiveConfigurationsPassChecklist() {
        let cnConfig = ReleaseArchiveAndTestFlightChecklistContract.XCConfigOverrides(
            codeSigningAllowed: "YES",
            developmentTeam: "A1B2C3D4E5",
            productBundleIdentifier: "cn.chengyinhub.questify",
            questifyMarket: "CN",
            questifyAPIBaseURL: "https://cn-gateway.chengyinhub.com",
            questifySessionRealm: "cn-prod"
        )
        let cnResult = ReleaseArchiveAndTestFlightChecklistContract.evaluateChecklist(xcconfig: cnConfig)
        XCTAssertTrue(cnResult.isReadyForArchive)
        XCTAssertEqual(cnResult.status, .readyForArchive)
        XCTAssertTrue(cnResult.blockerCodes.isEmpty)
        XCTAssertEqual(cnResult.normalizedMarket, "CN")

        let usConfig = ReleaseArchiveAndTestFlightChecklistContract.XCConfigOverrides(
            codeSigningAllowed: "YES",
            developmentTeam: "Z9Y8X7W6V5",
            productBundleIdentifier: "us.chengyinhub.questify",
            questifyMarket: "US",
            questifyAPIBaseURL: "https://us-gateway.chengyinhub.com",
            questifySessionRealm: "us-prod"
        )
        let usResult = ReleaseArchiveAndTestFlightChecklistContract.evaluateChecklist(xcconfig: usConfig)
        XCTAssertTrue(usResult.isReadyForArchive)
        XCTAssertEqual(usResult.status, .readyForArchive)
        XCTAssertTrue(usResult.blockerCodes.isEmpty)
        XCTAssertEqual(usResult.normalizedMarket, "US")
    }

    func testForbiddenLegacyHostAndMismatchedSessionRealmAreBlocked() {
        let legacyHostConfig = ReleaseArchiveAndTestFlightChecklistContract.XCConfigOverrides(
            codeSigningAllowed: "YES",
            developmentTeam: "A1B2C3D4E5",
            productBundleIdentifier: "cn.chengyinhub.questify",
            questifyMarket: "CN",
            questifyAPIBaseURL: "https://47.103.124.64/prod",
            questifySessionRealm: "us-prod"
        )
        let result = ReleaseArchiveAndTestFlightChecklistContract.evaluateChecklist(xcconfig: legacyHostConfig)

        XCTAssertFalse(result.isReadyForArchive)
        XCTAssertTrue(result.blockerCodes.contains(.forbiddenLegacyHostAPIBaseURL))
        XCTAssertTrue(result.blockerCodes.contains(.missingOrMismatchedSessionRealm))
    }

    func testPreArchiveCommandSuiteRequiresAllFiveVerificationCommands() {
        let validConfig = ReleaseArchiveAndTestFlightChecklistContract.XCConfigOverrides(
            codeSigningAllowed: "YES",
            developmentTeam: "A1B2C3D4E5",
            productBundleIdentifier: "cn.chengyinhub.questify",
            questifyMarket: "CN",
            questifyAPIBaseURL: "https://cn-gateway.chengyinhub.com",
            questifySessionRealm: "cn-prod"
        )
        let partialSuite = ReleaseArchiveAndTestFlightChecklistContract.PreArchiveSuiteReport(
            passedCommands: [.generateProject, .checkScaffold, .checkRoamPrivateTools]
        )

        let result = ReleaseArchiveAndTestFlightChecklistContract.evaluateChecklist(
            xcconfig: validConfig,
            preArchiveSuite: partialSuite,
            userInfoRoleAdmissionVerified: false,
            failClosedAllowlistsIntact: false
        )

        XCTAssertFalse(result.isReadyForArchive)
        XCTAssertEqual(result.missingPreArchiveCommands, [.currentCICheck, .testCurrentCI])
        XCTAssertTrue(result.blockerCodes.contains(.preArchiveVerificationIncomplete))
        XCTAssertTrue(result.blockerCodes.contains(.userInfoRoleAdmissionNotVerified))
        XCTAssertTrue(result.blockerCodes.contains(.failClosedAllowlistsViolated))
        XCTAssertEqual(
            ReleaseArchiveAndTestFlightChecklistContract.PreArchiveCommand.allCases.map(\.rawValue),
            [
                "generate_project.py",
                "check_scaffold.py",
                "check_roam_private_tools.py",
                "current_ci.py check",
                "test_current_ci"
            ]
        )
    }
}
