import XCTest
@testable import QuestifyCore

final class RegionalEndpointAllowlistAuditTests: XCTestCase {
    private let cnBaseURL = "https://cn-api.example.com/v1"
    private let usBaseURL = "https://us-api.example.com/v1"

    func testHighRiskWriteRoutesRemainBlockedByDefaultInBothMarkets() {
        let expectedRoutes: Set<String> = [
            "/api/asset/withdraw",
            "/api/pay/create",
            "/api/npc/chat/delete",
            "/api/topic/like",
            "/api/user/sms/send",
            "/api/merchant/decor/save"
        ]
        XCTAssertEqual(Set(RegionalEndpointAllowlistAudit.requiredHighRiskWriteRoutes), expectedRoutes)

        let approvedBaseURLs: [RegionalMarket: Set<String>] = [
            .china: [cnBaseURL],
            .unitedStates: [usBaseURL]
        ]

        for (market, baseURL) in [(RegionalMarket.china, cnBaseURL), (.unitedStates, usBaseURL)] {
            let report = RegionalEndpointAllowlistAudit.audit(
                market: market,
                baseURL: baseURL,
                approvedBaseURLs: approvedBaseURLs
            )
            XCTAssertTrue(report.isBaseURLApproved)
            XCTAssertTrue(report.isFailClosedDefaultCompliant)
            XCTAssertTrue(report.passesReleasePreflight)
            XCTAssertTrue(report.allowlistedHighRiskRoutes.isEmpty)
            XCTAssertEqual(Set(report.blockedHighRiskRoutes), expectedRoutes)

            for route in RegionalHighRiskWriteRoute.allCases {
                let decision = report.decision(for: route)
                XCTAssertNotNil(decision)
                XCTAssertEqual(decision?.isHighRiskWrite, true)
                XCTAssertEqual(decision?.isAllowed, false)
                XCTAssertEqual(decision?.rejectionReason, .highRiskWriteBlockedByDefault)
            }
        }
    }

    func testLegacyMiniProgramHostIsAlwaysRejectedAcrossBaseAndCandidateURLs() {
        let legacyURLs = [
            "http://47.103.124.64:8080/api/pay/create",
            "https://47.103.124.64/api/user/sms/send",
            "https://47.103.124.64:8443/api/asset/withdraw"
        ]

        for legacy in legacyURLs {
            XCTAssertTrue(RegionalEndpointAllowlistAudit.targetsLegacyMiniProgramHost(legacy))
            let decision = RegionalEndpointAllowlistAudit.evaluateEndpoint(
                urlOrPath: legacy,
                market: .china,
                baseURL: cnBaseURL,
                approvedBaseURLs: [.china: [cnBaseURL]],
                allowlistedWriteRoutes: [.china: Set(RegionalHighRiskWriteRoute.canonicalPaths)]
            )
            XCTAssertFalse(decision.isAllowed)
            XCTAssertEqual(decision.rejectionReason, .legacyMiniProgramHostRejected)
        }

        let reportWithLegacyBase = RegionalEndpointAllowlistAudit.audit(
            market: .china,
            baseURL: "https://47.103.124.64/api",
            approvedBaseURLs: [.china: ["https://47.103.124.64/api"]],
            allowlistedWriteRoutes: [.china: ["/api/user/sms/send"]],
            additionalCandidateURLs: ["http://47.103.124.64:8080/api/topic/like"]
        )
        XCTAssertFalse(reportWithLegacyBase.isBaseURLApproved)
        XCTAssertFalse(reportWithLegacyBase.passesReleasePreflight)
        XCTAssertFalse(reportWithLegacyBase.isFailClosedDefaultCompliant)
        XCTAssertEqual(
            reportWithLegacyBase.rejectedLegacyMiniProgramURLs,
            [
                "http://47.103.124.64:8080/api/topic/like",
                "https://47.103.124.64/api"
            ]
        )
        XCTAssertTrue(reportWithLegacyBase.allowlistedHighRiskRoutes.isEmpty)
    }

    func testCrossMarketIsolationPreventsCNAllowlistFromUnlockingUSRoutesAndViceVersa() {
        let approvedBaseURLs: [RegionalMarket: Set<String>] = [
            .china: [cnBaseURL],
            .unitedStates: [usBaseURL]
        ]
        let allowlistedRoutes: [RegionalMarket: Set<String>] = [
            .china: ["/api/user/sms/send", "/api/topic/like"],
            .unitedStates: ["/api/merchant/decor/save"]
        ]

        let usReportWithCNRoutes = RegionalEndpointAllowlistAudit.audit(
            market: .unitedStates,
            baseURL: usBaseURL,
            approvedBaseURLs: approvedBaseURLs,
            allowlistedWriteRoutes: allowlistedRoutes
        )
        XCTAssertTrue(usReportWithCNRoutes.isBaseURLApproved)
        XCTAssertEqual(usReportWithCNRoutes.allowlistedHighRiskRoutes, ["/api/merchant/decor/save"])
        XCTAssertEqual(usReportWithCNRoutes.decision(for: .userSMSSend)?.isAllowed, false)
        XCTAssertEqual(usReportWithCNRoutes.decision(for: .topicLike)?.isAllowed, false)
        XCTAssertEqual(usReportWithCNRoutes.decision(for: .merchantDecorSave)?.isAllowed, true)

        let crossMarketBaseReport = RegionalEndpointAllowlistAudit.audit(
            market: .unitedStates,
            baseURL: cnBaseURL,
            approvedBaseURLs: approvedBaseURLs,
            allowlistedWriteRoutes: allowlistedRoutes
        )
        XCTAssertFalse(crossMarketBaseReport.isBaseURLApproved)
        XCTAssertFalse(crossMarketBaseReport.passesReleasePreflight)
        XCTAssertTrue(crossMarketBaseReport.allowlistedHighRiskRoutes.isEmpty)
        XCTAssertEqual(
            crossMarketBaseReport.violations,
            [.crossMarketBaseURLContamination(cnBaseURL)]
        )
        XCTAssertEqual(
            crossMarketBaseReport.decision(for: .merchantDecorSave)?.rejectionReason,
            .crossMarketEndpointIsolation
        )
    }

    func testExplicitPerMarketAllowlistAndSignedOffHighRiskVerification() {
        let approvedBaseURLs: [RegionalMarket: Set<String>] = [.china: [cnBaseURL]]
        let allowlistedRoutes: [RegionalMarket: Set<String>] = [
            .china: ["api/user/sms/send", "/api/pay/create"]
        ]

        let unsignedReport = RegionalEndpointAllowlistAudit.audit(
            market: .china,
            baseURL: cnBaseURL,
            approvedBaseURLs: approvedBaseURLs,
            allowlistedWriteRoutes: allowlistedRoutes,
            signedOffHighRiskRoutes: [.china: [.userSMSSend]]
        )
        XCTAssertEqual(
            unsignedReport.allowlistedHighRiskRoutes,
            ["/api/pay/create", "/api/user/sms/send"]
        )
        XCTAssertFalse(unsignedReport.passesReleasePreflight)
        XCTAssertEqual(
            unsignedReport.violations,
            [.unapprovedHighRiskWriteEnabled("/api/pay/create")]
        )

        let signedReport = RegionalEndpointAllowlistAudit.audit(
            market: .china,
            baseURL: cnBaseURL,
            approvedBaseURLs: approvedBaseURLs,
            allowlistedWriteRoutes: allowlistedRoutes,
            signedOffHighRiskRoutes: [.china: [.userSMSSend, .payCreate]]
        )
        XCTAssertTrue(signedReport.passesReleasePreflight)
        XCTAssertTrue(signedReport.violations.isEmpty)
        XCTAssertEqual(signedReport.decision(forPath: "api/user/sms/send")?.isAllowed, true)
        XCTAssertEqual(signedReport.decision(forPath: "/api/pay/create")?.isAllowed, true)
        XCTAssertEqual(signedReport.decision(forPath: "/api/asset/withdraw")?.isAllowed, false)
        XCTAssertEqual(signedReport.decision(forPath: "/api/npc/chat/delete")?.isAllowed, false)
    }
}
