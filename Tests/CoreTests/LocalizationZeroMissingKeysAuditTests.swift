import XCTest
@testable import QuestifyCore

final class LocalizationZeroMissingKeysAuditTests: XCTestCase {
    func testPassingCatalogEntriesAcrossAllFourTablesReportZeroViolations() {
        let entries: [LocalizationCatalogEntry] = [
            LocalizationCatalogEntry(
                catalog: .localizable,
                key: "wallet.withdrawals",
                translations: [.en: "Withdrawal Records", .zhHans: "提现记录"]
            ),
            LocalizationCatalogEntry(
                catalog: .roamPrivateTools,
                key: "roam.private.title",
                translations: [.en: "Private Tools (%lld)", .zhHans: "私享工具 (%lld)"]
            ),
            LocalizationCatalogEntry(
                catalog: .merchantStoreParity,
                key: "merchant.store.title",
                translations: [.en: "Store Management", .zhHans: "门店管理"]
            ),
            LocalizationCatalogEntry(
                catalog: .memberProfile,
                key: "member.profile.nickname",
                translations: [.en: "Nickname: %@", .zhHans: "昵称：%@"]
            )
        ]

        let report = LocalizationZeroMissingKeysAudit.runAudit(entries: entries)
        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.totalEntriesAudited, 4)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertEqual(LocalizationCatalogName.allCases.map(\.tableName), [
            "Localizable",
            "RoamPrivateTools",
            "MerchantStoreParity",
            "MemberProfile"
        ])
    }

    func testMissingLocaleAndUntranslatedStateAreDetected() {
        let missingZh = LocalizationCatalogEntry(
            catalog: .localizable,
            key: "withdrawal.apply.title",
            translations: [.en: "Withdrawal Application"]
        )
        let untranslatedEn = LocalizationCatalogEntry(
            catalog: .memberProfile,
            key: "member.profile.bio",
            translations: [.en: "Bio", .zhHans: "个人简介"],
            stateByLocale: [.en: "needs_review", .zhHans: "translated"]
        )

        let report = LocalizationZeroMissingKeysAudit.runAudit(entries: [missingZh, untranslatedEn])
        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(report.violations, [
            .missingLocale(catalog: .localizable, key: "withdrawal.apply.title", locale: .zhHans),
            .untranslatedState(catalog: .memberProfile, key: "member.profile.bio", locale: .en, state: "needs_review")
        ])
    }

    func testEmptyTranslationsUnresolvedPlaceholdersAndFormatMismatchesAreRejected() {
        let emptyZh = LocalizationCatalogEntry(
            catalog: .roamPrivateTools,
            key: "roam.tool.empty",
            translations: [.en: "Ready", .zhHans: "   "]
        )
        let unresolvedTemplate = LocalizationCatalogEntry(
            catalog: .merchantStoreParity,
            key: "merchant.store.banner",
            translations: [.en: "Store {{name}}", .zhHans: "门店名称"]
        )
        let mismatchedSpecifiers = LocalizationCatalogEntry(
            catalog: .localizable,
            key: "coupon.count.summary",
            translations: [.en: "%lld coupons for %@", .zhHans: "%lld 张优惠券"]
        )

        let report = LocalizationZeroMissingKeysAudit.runAudit(
            entries: [emptyZh, unresolvedTemplate, mismatchedSpecifiers]
        )
        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.emptyTranslation(catalog: .roamPrivateTools, key: "roam.tool.empty", locale: .zhHans)))
        XCTAssertTrue(report.violations.contains(.unresolvedPlaceholder(catalog: .merchantStoreParity, key: "merchant.store.banner", locale: .en)))
        XCTAssertTrue(report.violations.contains(
            .formatSpecifierMismatch(
                catalog: .localizable,
                key: "coupon.count.summary",
                enSpecifiers: ["%@", "%lld"],
                zhSpecifiers: ["%lld"]
            )
        ))
    }

    func testSwiftUIViewComplianceAcceptsVerbatimAndFlagsUntrackedDotKeys() {
        let compliantSource = """
        struct StoryWalkingAndFogSectionView: View {
            var body: some View {
                VStack {
                    Text(verbatim: "当前导航站点 (W15.1)")
                        .accessibilityIdentifier("story.walking.currentStop")
                    Text("map.entry.title", tableName: "MapCoreEntry")
                }
            }
        }
        """
        let nonCompliantSource = """
        struct BadReleaseDiagnosticsView: View {
            var body: some View {
                VStack {
                    Text("release.diagnostics.untrackedKey")
                    Text(verbatim: "正常文本")
                }
            }
        }
        """

        let compliantViolations = LocalizationZeroMissingKeysAudit.auditSwiftUIViewSource(
            viewName: "StoryWalkingAndFogSectionView",
            source: compliantSource
        )
        XCTAssertTrue(compliantViolations.isEmpty)

        let report = LocalizationZeroMissingKeysAudit.runAudit(
            entries: [],
            viewSources: [
                ("StoryWalkingAndFogSectionView", compliantSource),
                ("BadReleaseDiagnosticsView", nonCompliantSource)
            ]
        )
        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(report.totalViewsAudited, 2)
        XCTAssertEqual(report.violations, [
            .untrackedDotKeyInView(viewName: "BadReleaseDiagnosticsView", key: "release.diagnostics.untrackedKey")
        ])
    }
}
