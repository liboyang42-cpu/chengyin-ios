import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class ReleaseArchiveChecklistSectionViewTests: XCTestCase {
    func testUnsignedWorkspaceDefaultHoldsArchiveAndListsAllEightGates() {
        let snapshot = ReleaseArchiveChecklistSnapshot.unsignedWorkspaceDefault
        XCTAssertFalse(snapshot.isArchiveReady)
        XCTAssertEqual(snapshot.items.map(\.id), [
            "local-xcconfig",
            "code-signing",
            "development-team",
            "bundle-identifier",
            "questify-market",
            "api-base-url",
            "session-realm",
            "cli-verification"
        ])
        XCTAssertEqual(snapshot.readyCount, 1)
        XCTAssertEqual(snapshot.blockedCount, 1)
        XCTAssertEqual(snapshot.pendingCount, 6)

        let view = ReleaseArchiveChecklistSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot, snapshot)
    }

    func testForbiddenLegacyOriginIPBlocksArchiveEvenWhenSigned() {
        let snapshot = ReleaseArchiveChecklistSnapshot.evaluate(
            localXcconfigPresent: true,
            codeSigningAllowed: "YES",
            developmentTeam: "TEAM99ABCD",
            bundleIdentifier: "com.chengyin.questify",
            market: "CN",
            apiBaseURL: "https://47.103.124.64/prod-api",
            sessionRealm: "cn-prod-v1",
            cliChecksPassed: true
        )
        XCTAssertFalse(snapshot.isArchiveReady)
        let urlGate = snapshot.items.first { $0.id == "api-base-url" }
        XCTAssertEqual(urlGate?.status, .blocked)
        XCTAssertEqual(urlGate?.badgeText, "BLOCKED")
    }

    func testFullyConfiguredReleaseOverridesBecomeArchiveReady() {
        let snapshot = ReleaseArchiveChecklistSnapshot.evaluate(
            localXcconfigPresent: true,
            codeSigningAllowed: "YES",
            developmentTeam: "TEAM99ABCD",
            bundleIdentifier: "com.chengyin.questify",
            market: "CN",
            apiBaseURL: "https://api.example.com",
            sessionRealm: "cn-prod-v1",
            cliChecksPassed: true
        )
        XCTAssertTrue(snapshot.isArchiveReady)
        XCTAssertEqual(snapshot.readyCount, 8)
        XCTAssertEqual(snapshot.blockedCount, 0)
        XCTAssertEqual(snapshot.pendingCount, 0)
        XCTAssertEqual(snapshot.summaryText, "就绪 8/8 · 待配置 0 · 阻断 0")

        let view = ReleaseArchiveChecklistSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertTrue(view.snapshot.isArchiveReady)
    }
}
