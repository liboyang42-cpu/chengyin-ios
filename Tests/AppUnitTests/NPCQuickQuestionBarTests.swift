import XCTest
@testable import Questify

/// Resource/composer contracts only; simulator rendering is a separate check.
final class NPCQuickQuestionBarTests: XCTestCase {
    func testEveryQuestionHasEnglishAndChineseTextInsteadOfRawKeys() {
        for question in NPCQuickQuestion.allCases {
            let english = NPCQuickQuestionText.question(question, locale: Locale(identifier: "en"))
            let chinese = NPCQuickQuestionText.question(question, locale: Locale(identifier: "zh-Hans"))
            XCTAssertFalse(english.isEmpty); XCTAssertFalse(chinese.isEmpty)
            XCTAssertNotEqual(english, question.questionKey); XCTAssertNotEqual(chinese, question.questionKey)
            XCTAssertNotEqual(english, chinese); XCTAssertLessThanOrEqual(english.utf16.count, 500)
        }
    }
    func testQuestionTextFollowsExplicitAppLocale() {
        XCTAssertEqual(NPCQuickQuestionText.question(.order, locale: Locale(identifier: "en")), "What would you recommend ordering here? If you don't have current information, please say so.")
        XCTAssertEqual(NPCQuickQuestionText.question(.specialties, locale: Locale(identifier: "zh-Hans")), "这家店有什么特色？请只根据已确认的公开信息介绍，不确定的地方请说明。")
    }
    func testGameQuestionExplicitlyAvoidsAnswersAndLockedClues() {
        let english = NPCQuickQuestionText.question(.publicRules, locale: Locale(identifier: "en"))
        let chinese = NPCQuickQuestionText.question(.publicRules, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(english.contains("public rules")); XCTAssertTrue(english.contains("locked clues"))
        XCTAssertTrue(chinese.contains("公开规则")); XCTAssertTrue(chinese.contains("未解锁"))
    }
}
