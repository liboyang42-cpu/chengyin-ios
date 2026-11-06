import Foundation
import XCTest
@testable import Questify

/// Real bundled language resources; does not claim screenshot or VoiceOver validation.
@MainActor final class NativeStoryWalkingAuthorLocalizationTests: XCTestCase {
    private let keys = [
        "walkingAuthor.acknowledge",
        "walkingAuthor.alternative",
        "walkingAuthor.apply",
        "walkingAuthor.approach",
        "walkingAuthor.authorization.title",
        "walkingAuthor.back",
        "walkingAuthor.businessTime",
        "walkingAuthor.choose",
        "walkingAuthor.closed.chooseNo",
        "walkingAuthor.closed.chooseYes",
        "walkingAuthor.closed.no",
        "walkingAuthor.closed.required",
        "walkingAuthor.closed.yes",
        "walkingAuthor.confirmation.title",
        "walkingAuthor.datum",
        "walkingAuthor.discard.cancel",
        "walkingAuthor.discard.confirm",
        "walkingAuthor.discard.message",
        "walkingAuthor.discard.title",
        "walkingAuthor.duration.value",
        "walkingAuthor.entrance.add",
        "walkingAuthor.entrance.remove",
        "walkingAuthor.entrance.undeclared",
        "walkingAuthor.entranceScope",
        "walkingAuthor.entry",
        "walkingAuthor.floor",
        "walkingAuthor.invalid",
        "walkingAuthor.label",
        "walkingAuthor.latitude",
        "walkingAuthor.legacy.scope",
        "walkingAuthor.legacy.title",
        "walkingAuthor.legacy.upgrade",
        "walkingAuthor.longitude",
        "walkingAuthor.node.add",
        "walkingAuthor.node.number",
        "walkingAuthor.node.remove",
        "walkingAuthor.nodes.allAdded",
        "walkingAuthor.nodes.empty",
        "walkingAuthor.nodes.noneSaved",
        "walkingAuthor.nodes.limit",
        "walkingAuthor.notice.title",
        "walkingAuthor.region",
        "walkingAuthor.retired.message",
        "walkingAuthor.retired.title",
        "walkingAuthor.return",
        "walkingAuthor.reviewScope",
        "walkingAuthor.saveScope",
        "walkingAuthor.saveUnconfirmed",
        "walkingAuthor.scope",
        "walkingAuthor.scope.title",
        "walkingAuthor.source",
        "walkingAuthor.title",
        "walkingAuthor.ttl",
        "walkingAuthor.unavailable",
        "walkingAuthor.unsupported"
    ]
    private func text(_ key: String, language: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
            table: "NativeStoryWalkingAuthor", locale: Locale(identifier: language)))
    }
    func testEveryNormalFieldChoiceReviewErrorAndReturnStateResolvesInBothLanguages() {
        for key in keys {
            let english = text(key, language: "en"), chinese = text(key, language: "zh-Hans")
            XCTAssertFalse(english.isEmpty, key); XCTAssertNotEqual(english, key)
            XCTAssertFalse(chinese.isEmpty, key); XCTAssertNotEqual(chinese, key)
            XCTAssertNotEqual(english, chinese, key)
        }
    }
    func testSwitchingLocaleDoesNotCacheAPreviousLanguage() {
        for key in ["walkingAuthor.title", "walkingAuthor.retired.message", "walkingAuthor.saveUnconfirmed", "walkingAuthor.discard.message"] {
            let first = text(key, language: "en")
            XCTAssertNotEqual(first, text(key, language: "zh-Hans"))
            XCTAssertEqual(first, text(key, language: "en"))
        }
    }
    func testRetiredCopyDoesNotPromiseToRetainOrAutomaticallyRestoreAnUnconfirmedCopy() {
        let english = text("walkingAuthor.retired.message", language: "en")
        let chinese = text("walkingAuthor.retired.message", language: "zh-Hans")
        XCTAssertTrue(english.contains("is cleared")); XCTAssertTrue(english.contains("reopen entrance details"))
        XCTAssertTrue(english.contains("will not be restored or written back automatically"))
        XCTAssertTrue(chinese.contains("副本已清除")); XCTAssertTrue(chinese.contains("再重新打开"))
        XCTAssertTrue(chinese.contains("不会自动恢复或写回"))
        XCTAssertEqual(text("walkingAuthor.return", language: "en"), "Return to the original topic draft")
        XCTAssertEqual(text("walkingAuthor.return", language: "zh-Hans"), "返回原主题草稿")
    }
    func testSaveUnconfirmedAndUnsupportedRemainDistinctFromRetirement() {
        for language in ["en", "zh-Hans"] {
            let notices = ["walkingAuthor.saveUnconfirmed", "walkingAuthor.invalid", "walkingAuthor.unsupported", "walkingAuthor.unavailable", "walkingAuthor.retired.message"]
                .map { text($0, language: language) }
            XCTAssertEqual(Set(notices).count, notices.count)
        }
        XCTAssertTrue(text("walkingAuthor.saveUnconfirmed", language: "en").contains("retains your configuration copy"))
        XCTAssertTrue(text("walkingAuthor.saveUnconfirmed", language: "zh-Hans").contains("副本保留，可重试"))
        XCTAssertTrue(text("walkingAuthor.unsupported", language: "en").contains("Unknown fields have not been overwritten"))
    }
    func testUpgradeDiscardAndScopeCopyPreservesExplicitLocalOnlyActions() {
        XCTAssertTrue(text("walkingAuthor.legacy.scope", language: "en").contains("explicit upgrade, save and the original review"))
        XCTAssertTrue(text("walkingAuthor.legacy.scope", language: "zh-Hans").contains("明确升级、保存并经原审核"))
        XCTAssertTrue(text("walkingAuthor.discard.message", language: "en").contains("does not write changes, undo a save or confirm an earlier unconfirmed save"))
        XCTAssertTrue(text("walkingAuthor.discard.message", language: "zh-Hans").contains("不会写入、撤销或确认此前未确认的保存结果"))
        XCTAssertTrue(text("walkingAuthor.saveScope", language: "en").contains("does not save to the server, request permissions or enable location"))
        XCTAssertTrue(text("walkingAuthor.saveScope", language: "zh-Hans").contains("不在此保存服务器、申请新权限或启用定位"))
    }
    func testOriginalNodeAndStoredDurationFormatsKeepTheActualSourceValues() {
        for (language, expectedNode, expectedDuration) in [("en", "Original node #22", "60 seconds"), ("zh-Hans", "原节点 #22", "60 秒")] {
            let locale = Locale(identifier: language)
            XCTAssertEqual(String(format: text("walkingAuthor.node.number", language: language), locale: locale, Int64(22)), expectedNode)
            XCTAssertEqual(String(format: text("walkingAuthor.duration.value", language: language), locale: locale, "60"), expectedDuration)
        }
    }
}
