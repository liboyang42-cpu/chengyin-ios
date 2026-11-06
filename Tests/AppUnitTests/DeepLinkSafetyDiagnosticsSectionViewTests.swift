import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class DeepLinkSafetyDiagnosticsSectionViewTests: XCTestCase {
    private let allowlist: Set<String> = ["links.questify.example.test"]

    func testDefaultRulesAndStandardSnapshotEnforceAllFourDeepLinkSafetyInvariants() {
        let snapshot = DeepLinkSafetySnapshot.standard
        XCTAssertEqual(snapshot.rules.count, 4)
        XCTAssertEqual(snapshot.enforcedRuleCount, 4)
        XCTAssertTrue(snapshot.allRulesEnforced)
        XCTAssertFalse(snapshot.allowsAutoMutation)
        XCTAssertEqual(
            snapshot.rules.map(\.category),
            [
                .httpsHostAllowlist,
                .incompleteMemberIDFallback,
                .crossMarketRealmIsolation,
                .zeroAutoMutationGuarantee,
            ]
        )
        XCTAssertEqual(
            snapshot.rules.map(\.id),
            [
                "https-host-allowlist",
                "w2-12-member-id-fallback",
                "cross-market-realm-isolation",
                "zero-auto-mutation",
            ]
        )

        let view = DeepLinkSafetyDiagnosticsSectionView(snapshot: snapshot)
        _ = view.body
    }

    func testEvaluateMemberCardLinkEnforcesHTTPSAllowlistCrossMarketIsolationZeroMutationAndW212Fallback() {
        // 1. Non-HTTPS or untrusted host is rejected.
        let untrustedScheme = DeepLinkSafetySnapshot.evaluateMemberCardLink(
            scheme: "http",
            host: "links.questify.example.test",
            allowlistedHTTPSHosts: allowlist,
            linkMarketCode: "cn",
            activeMarketCode: "cn",
            linkRealm: "cn-prod",
            activeAuthRealm: "cn-prod",
            memberID: 101
        )
        XCTAssertEqual(untrustedScheme.lastEvaluatedOutcome, .rejectedUntrustedHostOrScheme)
        _ = DeepLinkSafetyDiagnosticsSectionView(snapshot: untrustedScheme).body

        let untrustedHost = DeepLinkSafetySnapshot.evaluateMemberCardLink(
            scheme: "https",
            host: "evil.example.test",
            allowlistedHTTPSHosts: allowlist,
            linkMarketCode: "cn",
            activeMarketCode: "cn",
            linkRealm: "cn-prod",
            activeAuthRealm: "cn-prod",
            memberID: 101
        )
        XCTAssertEqual(untrustedHost.lastEvaluatedOutcome, .rejectedUntrustedHostOrScheme)

        // 2. Cross-market or cross-realm link is rejected.
        let crossMarket = DeepLinkSafetySnapshot.evaluateMemberCardLink(
            scheme: "https",
            host: "links.questify.example.test",
            allowlistedHTTPSHosts: allowlist,
            linkMarketCode: "sea",
            activeMarketCode: "cn",
            linkRealm: "sea-prod",
            activeAuthRealm: "cn-prod",
            memberID: 101
        )
        XCTAssertEqual(crossMarket.lastEvaluatedOutcome, .rejectedCrossMarketRealm)
        _ = DeepLinkSafetyDiagnosticsSectionView(snapshot: crossMarket).body

        // 3. Any auto-mutation attempt is rejected.
        let mutationAttempt = DeepLinkSafetySnapshot.evaluateMemberCardLink(
            scheme: "https",
            host: "links.questify.example.test",
            allowlistedHTTPSHosts: allowlist,
            linkMarketCode: "cn",
            activeMarketCode: "cn",
            linkRealm: "cn-prod",
            activeAuthRealm: "cn-prod",
            memberID: 101,
            attemptsMutation: true
        )
        XCTAssertEqual(mutationAttempt.lastEvaluatedOutcome, .rejectedMutationAttempt)
        XCTAssertFalse(mutationAttempt.allowsAutoMutation)
        _ = DeepLinkSafetyDiagnosticsSectionView(snapshot: mutationAttempt).body

        // 4. w2-12: nil, 0, or negative memberID routes to incompleteMemberIDFallback.
        for invalidMemberID in [nil, 0, -9] {
            let fallback = DeepLinkSafetySnapshot.evaluateMemberCardLink(
                scheme: "https",
                host: "links.questify.example.test",
                allowlistedHTTPSHosts: allowlist,
                linkMarketCode: "cn",
                activeMarketCode: "cn",
                linkRealm: "cn-prod",
                activeAuthRealm: "cn-prod",
                memberID: invalidMemberID
            )
            XCTAssertEqual(fallback.lastEvaluatedOutcome, .incompleteMemberIDFallback)
            XCTAssertTrue(fallback.lastEvaluatedSummary.contains("w2-12"))
            _ = DeepLinkSafetyDiagnosticsSectionView(snapshot: fallback).body
        }

        // 5. Valid read-only link with positive memberID is accepted.
        let accepted = DeepLinkSafetySnapshot.evaluateMemberCardLink(
            scheme: "https",
            host: "links.questify.example.test",
            allowlistedHTTPSHosts: allowlist,
            linkMarketCode: "cn",
            activeMarketCode: "cn",
            linkRealm: "cn-prod",
            activeAuthRealm: "cn-prod",
            memberID: 88
        )
        XCTAssertEqual(accepted.lastEvaluatedOutcome, .acceptedReadOnlyRoute)
        XCTAssertTrue(accepted.allRulesEnforced)
        _ = DeepLinkSafetyDiagnosticsSectionView(snapshot: accepted).body
    }
}
