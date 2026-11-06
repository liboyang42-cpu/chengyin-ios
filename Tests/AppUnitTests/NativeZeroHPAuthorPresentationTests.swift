import Foundation
import XCTest
@testable import Questify

@MainActor final class NativeZeroHPAuthorPresentationTests: XCTestCase {
    private let en = NativeZeroHPAuthorPresentation(locale: Locale(identifier: "en"))
    private let zh = NativeZeroHPAuthorPresentation(locale: Locale(identifier: "zh-Hans"))

    func testEveryKnownSourceDiagnosticHasBothPackagedTranslations() {
        for (source, key) in NativeZeroHPAuthorPresentation.keys {
            XCTAssertEqual(zh.message(source), source, key)
            XCTAssertNotEqual(en.message(source), source, key)
            XCTAssertFalse(en.text(key).isEmpty, key)
            XCTAssertNotEqual(en.text(key), key)
        }
    }
    func testControllerFailureStatesRetainLocalAndServerBoundaries() {
        XCTAssertTrue(en.message("原本地保存未确认；已保留归零策略与挑战副本，请重试本地保存。尚未保存服务器或发布。").contains("Nothing has been saved to the server or published"))
        XCTAssertTrue(en.message("权限、玩法版本或引用未能确认，未覆盖原草稿。请重试读取；服务器保存尚未发起。").contains("no server save has started"))
        XCTAssertTrue(en.message("当前项目不可完整编辑，请返回原项目读取权限与版本。").contains("Full editing is unavailable"))
    }
    func testDynamicBoundsAndResourceErrorsKeepOriginalNumbers() {
        XCTAssertEqual(en.message("恢复值须为 1 至 20 的整数"), "Recovery amount must be an integer from 1 to 20.")
        XCTAssertEqual(zh.message("恢复值须为 1 至 20 的整数"), "恢复值须为 1 至 20 的整数")
        XCTAssertEqual(en.message("hp上限须为1–20整数。"), "HP maximum must be an integer from 1 to 20.")
        XCTAssertEqual(en.message("节点 9007199254740993 已删除或未保存，请重新选择"), "Node 9007199254740993 was deleted or is not saved. Choose again.")
    }
    func testNodeNamesAndDiagnosticPathsAreNotFormatStrings() {
        let name = "我的：%@ e\u{301}"
        let reason = "这种玩法不能用作归零挑战"
        XCTAssertEqual(en.message(name + "：" + reason), name + ": This gameplay cannot be used as a zero-health challenge.")
        XCTAssertEqual(en.message("请先在原玩法编辑器修正结果或工具配置：outcomeRules.%@"), "Correct the outcome or tool settings in the original gameplay editor: outcomeRules.%@")
        XCTAssertEqual(en.format("zeroHP.node", "9007199254740993"), "Node 9007199254740993")
    }
    func testKnownPoliciesAreDisplayOnlyAndUnknownValuesStayLiteral() {
        XCTAssertEqual(NativeZeroHPAuthorDraft.Policy.allCases.map(\.rawValue), ["BLOCK_HP_COST", "THEME_FAIL", "CHALLENGE", "STEPS", "WAIT"])
        for policy in NativeZeroHPAuthorDraft.Policy.allCases {
            XCTAssertEqual(zh.message(policy.title), policy.title)
            XCTAssertNotEqual(en.message(policy.title), policy.title)
        }
        XCTAssertEqual(en.message("FUTURE_POLICY_%@"), "FUTURE_POLICY_%@")
        XCTAssertEqual(en.gameplay("future-game"), "future-game")
        for key in NativeZeroHPAuthorPolicy.challengeSections {
            XCTAssertNotEqual(en.gameplay(key), "zeroHP.gameplay." + key)
            XCTAssertNotEqual(zh.gameplay(key), "zeroHP.gameplay." + key)
        }
    }
    func testCompatibilityKeepsUnknownPolicyCustomNameAndReplyBytes() throws {
        let reply = "%@ 私人 e\u{301} 👩🏽‍💻", name = "生命值 %@ e\u{301}"
        let theme: [String: Any] = ["schemaVersion": 1, "hpName": name,
            "gameplayRuntime": ["survival": ["zeroHpPolicy": "FUTURE_%@", "zeroMessage": reply]]]
        var original = ProjectEditDraft()
        original.preserved["themeRuntimeConfig"] = .string(String(decoding: try JSONSerialization.data(withJSONObject: theme), as: UTF8.self))
        let draft = try NativeZeroHPAuthorDraft(draft: original)
        let before = ProjectEditPendingMaterials.exactData(original)
        XCTAssertTrue(draft.readOnly)
        for copy in [en, zh] {
            XCTAssertEqual(Array(copy.healthName(draft).utf8), Array(name.utf8))
            XCTAssertEqual(Array(copy.compatibility(draft).utf8), Array(("FUTURE_%@ · " + reply).utf8))
        }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft.original), before)
    }
    func testLanguageSwitchUsesCurrentLocaleAndNoCachedLanguage() {
        XCTAssertEqual(en.message("完成"), "Done")
        XCTAssertEqual(zh.message("完成"), "完成")
        XCTAssertEqual(en.message("完成"), "Done")
        XCTAssertTrue(en.text("zeroHP.doneHint").contains("Does not save to the server"))
    }
}
