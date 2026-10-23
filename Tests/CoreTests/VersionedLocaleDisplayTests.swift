import XCTest
@testable import QuestifyCore

final class VersionedLocaleDisplayTests: XCTestCase {
    private var fixed: Date {
        ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")!
    }

    func testFirstJourneyCnShanghaiAndUsIapLegalNotRunRecoverOriginal() {
        let cn = VersionedLocaleDisplay.profile(.cn)
        let us = VersionedLocaleDisplay.profile(.us)
        XCTAssertEqual(cn.version, 1)
        XCTAssertEqual(us.version, 1)
        XCTAssertEqual(VersionedLocaleDisplay.profileVersion, 1)
        XCTAssertEqual(cn.languageTag, "zh-CN")
        XCTAssertEqual(us.languageTag, "en-US")
        XCTAssertEqual(cn.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(us.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(cn.datePattern, "yyyy-MM-dd HH:mm:ss")
        XCTAssertEqual(us.datePattern, "MMM d, yyyy h:mm a")
        XCTAssertEqual(VersionedLocaleDisplay.format(.cn, instant: fixed), "2026-10-23 20:00:00")
        XCTAssertEqual(asciiSpaces(VersionedLocaleDisplay.format(.us, instant: fixed)), "Oct 23, 2026 8:00 AM")
        XCTAssertNotEqual(cn.paymentChannel, us.paymentChannel)
        XCTAssertTrue(cn.paymentChannel.contains("微信"))
        XCTAssertTrue(us.paymentChannel.contains("IAP"))
        XCTAssertTrue(us.paymentChannel.contains("线下核销仍不走 IAP"))
        XCTAssertEqual(VersionedLocaleDisplay.legalGateStatus(.appStoreReview), "NOT_RUN")
        XCTAssertEqual(VersionedLocaleDisplay.legalGateStatus(.productionDDL), VersionedLocaleDisplay.notRun)
    }

    func testUnknownInstantStaysUnknownNotEmptySuccess() {
        XCTAssertEqual(VersionedLocaleDisplay.format(.cn, instant: nil), "UNKNOWN")
        XCTAssertNotEqual(VersionedLocaleDisplay.format(.cn, instant: nil), "")
    }

    func testLegalAndStoreGatesStayNotRunAndNeverPass() {
        let gates = VersionedLocaleDisplay.legalGateStatuses()
        XCTAssertEqual(gates.count, VersionedLocaleDisplay.LegalGate.allCases.count)
        for gate in VersionedLocaleDisplay.LegalGate.allCases {
            XCTAssertEqual(gates[gate], VersionedLocaleDisplay.notRun)
            XCTAssertEqual(VersionedLocaleDisplay.legalGateStatus(gate), VersionedLocaleDisplay.notRun)
            XCTAssertNotEqual(VersionedLocaleDisplay.legalGateStatus(gate), "PASS")
            XCTAssertNotEqual(VersionedLocaleDisplay.legalGateStatus(gate), "PASSED")
        }
        XCTAssertEqual(
            VersionedLocaleDisplay.profile(.cn).asView()["legalGates"], VersionedLocaleDisplay.notRun)
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.icpFiling.rawValue, "ICP_FILING")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.privacyAgreement.rawValue, "PRIVACY_AGREEMENT")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.userAgreement.rawValue, "USER_AGREEMENT")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.wechatMiniprogramReview.rawValue, "WECHAT_MINIPROGRAM_REVIEW")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.appStoreReview.rawValue, "APP_STORE_REVIEW")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.playStoreReview.rawValue, "PLAY_STORE_REVIEW")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.productionCapacity.rawValue, "PRODUCTION_CAPACITY")
        XCTAssertEqual(VersionedLocaleDisplay.LegalGate.productionDDL.rawValue, "PRODUCTION_DDL")
    }

    private func asciiSpaces(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }
}
