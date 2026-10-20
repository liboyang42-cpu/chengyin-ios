import XCTest
@testable import QuestifyCore

final class MiniProgram99PageParityRegistryTests: XCTestCase {
    func testAllFourAlignmentDomainsArePresentAndMappedToDocs() {
        let domains = MiniProgram99PageParityRegistry.allDomains
        XCTAssertEqual(domains.map(\.rawValue), ["B", "C", "D", "E"])
        XCTAssertEqual(
            domains.map(\.alignmentDocPath),
            [
                "docs/alignment/xcx-ios-B-20261019.md",
                "docs/alignment/xcx-ios-C-20261019.md",
                "docs/alignment/xcx-ios-D-20261019.md",
                "docs/alignment/xcx-ios-E-20261019.md"
            ]
        )
    }

    func testAllTwentyOneWave2ScopesAreRegisteredInOrder() {
        let scopes = MiniProgram99PageParityRegistry.wave2Scopes
        XCTAssertEqual(scopes.count, 21)

        let expectedIDs = (1...21).map { String(format: "w2-%02d", $0) }
        XCTAssertEqual(scopes.map(\.scopeID), expectedIDs)

        XCTAssertEqual(MiniProgram99PageParityRegistry.scopes(for: .domainB).map(\.scopeID), ["w2-01", "w2-02", "w2-03", "w2-04", "w2-05"])
        XCTAssertEqual(MiniProgram99PageParityRegistry.scopes(for: .domainC).map(\.scopeID), ["w2-06", "w2-07"])
        XCTAssertEqual(MiniProgram99PageParityRegistry.scopes(for: .domainD).map(\.scopeID), ["w2-08", "w2-09", "w2-10", "w2-11"])
        XCTAssertEqual(
            MiniProgram99PageParityRegistry.scopes(for: .domainE).map(\.scopeID),
            ["w2-12", "w2-13", "w2-14", "w2-15", "w2-16", "w2-17", "w2-18", "w2-19", "w2-20", "w2-21"]
        )
    }

    func testRepresentativePagesCoverCoreMiniProgramRoutes() {
        let requiredPaths = [
            "pages/login/login",
            "pages/index/index",
            "pages/my/my",
            "pages/roam/index",
            "pages/play/index",
            "pages/team/index",
            "pages/club/index",
            "pages/merchant/index",
            "pages/publish/index",
            "pages/message/index"
        ]

        for path in requiredPaths {
            let entry = MiniProgram99PageParityRegistry.entry(forPagePath: path)
            XCTAssertNotNil(entry, "Expected representative parity entry for \(path)")
            XCTAssertFalse(entry?.nativeReaderOrPresentationContract.isEmpty ?? true)
            XCTAssertNotNil(MiniProgram99PageParityRegistry.scope(withID: entry?.wave2ScopeID ?? ""))
        }
    }

    func testWriteGatesRemainFailClosedByDefaultAcrossAllScopesAndPages() {
        XCTAssertTrue(MiniProgram99PageParityRegistry.areAllWriteGatesFailClosedByDefault)
        for scope in MiniProgram99PageParityRegistry.wave2Scopes {
            XCTAssertFalse(scope.writeGatePosture.isWriteGateEnabledByDefault, "Scope \(scope.scopeID) must remain fail-closed")
            XCTAssertFalse(scope.representativePagePaths.isEmpty)
            XCTAssertFalse(scope.nativeContracts.isEmpty)
        }
    }

    func testAll99BaselineEntriesDoNotUseDecisionModeAsSymbolAndLeaveUnverifiedMappingsBlank() {
        let entries = MiniProgram99PageParityRegistry.all99BaselinePageEntries
        XCTAssertEqual(entries.count, 99)

        for entry in entries {
            XCTAssertNotEqual(
                entry.nativeReaderOrPresentationContract,
                MiniProgram99PageDecisionMode.strictMiniProgramParity.rawValue,
                "Route \(entry.pagePath) must not use STRICT_1_TO_1_PARITY as a native contract symbol"
            )
            XCTAssertNotEqual(
                entry.nativeReaderOrPresentationContract,
                MiniProgram99PageDecisionMode.nativeSupersetEnhanced.rawValue,
                "Route \(entry.pagePath) must not use NATIVE_SUPERSET_ENHANCED as a native contract symbol"
            )
        }

        // Verified routes must carry concrete file, symbol, and host container
        let verifiedCapsule = MiniProgram99PageParityRegistry.entry(forPagePath: "subpackageTools/capsule/index")
        XCTAssertEqual(verifiedCapsule?.nativeReaderOrPresentationContract, "RoamCapsuleView")
        XCTAssertEqual(verifiedCapsule?.verifiedSourceFile, "App/RoamPassportPrivateToolsViews.swift")
        XCTAssertEqual(verifiedCapsule?.verifiedHostSymbol, "RoamPassportPrivateLinks")
        XCTAssertTrue(verifiedCapsule?.isSourceMappingVerified ?? false)

        // Unverified routes must leave symbol/file/host blank and report isSourceMappingVerified == false
        let unverifiedRoute = MiniProgram99PageParityRegistry.entry(forPagePath: "pages/talent/list/index")
        XCTAssertEqual(unverifiedRoute?.nativeReaderOrPresentationContract, "")
        XCTAssertEqual(unverifiedRoute?.verifiedSourceFile, "")
        XCTAssertEqual(unverifiedRoute?.verifiedHostSymbol, "")
        XCTAssertFalse(unverifiedRoute?.isSourceMappingVerified ?? true)
    }
}
