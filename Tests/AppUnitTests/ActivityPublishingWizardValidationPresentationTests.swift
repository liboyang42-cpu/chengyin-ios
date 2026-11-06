import XCTest
@testable import Questify

final class ActivityPublishingWizardValidationPresentationTests: XCTestCase {
    private func presentation(_ language: String) -> ActivityPublishingWizardValidationPresentation {
        .init(locale: Locale(identifier: language))
    }

    func testAllUnindexedReasonsInEnglishAndSimplifiedChinese() {
        let cases: [(String, String, String)] = [
            ("name", "Enter an activity name.", "请填写活动名称。"),
            ("addressName", "Enter the activity venue name.", "请填写活动地点名称。"),
            ("startDate", "Check the activity start date and time.", "请检查活动开始日期和时间。"),
            ("endDate", "Enter a valid activity end date and time later than the start.", "请填写有效的活动结束日期和时间，且晚于开始时间。"),
            ("categoryIds", "Choose at least one valid activity category.", "请至少选择一个有效的活动分类。"),
            ("description", "Enter an activity description.", "请填写活动介绍。"),
            ("templateId", "Choose a play template for the activity.", "请为活动选择玩法模板。"),
            ("imgUrl", "Add an activity cover.", "请添加活动封面。"),
            ("collaborators", "Check collaborators. Select valid members without duplicates.", "请检查协作者，选择有效会员且不要重复。"),
            ("ticket", "Check the ticket details and add at least one ticket type.", "请检查票务信息，并至少添加一个票种。")
        ]
        for (field, english, chinese) in cases {
            XCTAssertEqual(presentation("en").message(for: field), english, field)
            XCTAssertEqual(presentation("zh-Hans").message(for: field), chinese, field)
        }
    }

    func testEveryTicketReasonUsesOneBasedTicketNumbersInBothLanguages() {
        let cases: [(String, String, String)] = [
            ("ticketName", "Ticket %@: enter a name.", "第 %@ 个票种：请填写名称。"),
            ("ticketPrice", "Ticket %@: enter a valid price of zero or more.", "第 %@ 个票种：请填写有效且不小于零的价格。"),
            ("ticketStock", "Ticket %@: enter a whole-number stock greater than zero.", "第 %@ 个票种：请填写大于零的整数库存。"),
            ("ticketStart", "Ticket %@: check the start date and time.", "第 %@ 个票种：请检查开始日期和时间。"),
            ("ticketEnd", "Ticket %@: enter valid start and end dates and times, with the end after the start and both within the activity period.", "第 %@ 个票种：请填写有效的起止日期和时间，结束须晚于开始，且都在活动时段内。")
        ]
        for (prefix, english, chinese) in cases {
            for (index, number) in [(0, "1"), (1, "2"), (12, "13"), (Int.max - 1, String(Int.max))] {
                XCTAssertEqual(presentation("en").message(for: prefix + String(index)), english.replacingOccurrences(of: "%@", with: number))
                XCTAssertEqual(presentation("zh-Hans").message(for: prefix + String(index)), chinese.replacingOccurrences(of: "%@", with: number))
            }
        }
    }

    func testNilIsNeutralAndUnknownOrMalformedReasonsNeverEchoInternalCodes() {
        let unknown = ["", "futureField", "mapCoordinateDatum", "name ", "Name", " ticketName0", "ticketFuture0", "ticketName"]
        let suffixes = ["-1", "+1", "00", "01", "1.0", "1e2", " 1", "1 ", "1\n", "1tail", "١", "１", String(Int.max), String(Int.max) + "0"]
        let malformed = ["ticketName", "ticketPrice", "ticketStock", "ticketStart", "ticketEnd"].flatMap { prefix in
            suffixes.map { prefix + $0 }
        }
        for (language, neutral, fallback) in [
            ("en", "No field-specific validation message is currently shown.", "Check the activity details before continuing. A field-specific explanation is unavailable."),
            ("zh-Hans", "当前没有字段校验提示。", "请检查活动信息后继续，暂无法提供具体字段说明。")
        ] {
            let model = presentation(language)
            XCTAssertEqual(model.message(for: nil), neutral)
            for field in unknown + malformed {
                XCTAssertEqual(model.message(for: field), fallback, field)
                if !field.isEmpty { XCTAssertFalse(model.message(for: field).contains(field), field) }
            }
        }
    }

    func testAppLocaleCanSwitchBothWaysWithoutCachingTheLookupLanguage() {
        for language in ["en", "zh-Hans", "en"] {
            XCTAssertEqual(presentation(language).message(for: "name"), language == "en" ? "Enter an activity name." : "请填写活动名称。")
            XCTAssertEqual(presentation(language).message(for: "ticketName1"), language == "en" ? "Ticket 2: enter a name." : "第 2 个票种：请填写名称。")
        }
    }

    private func readyDraft() -> ActivityPublishDraft {
        var draft = ActivityPublishDraft()
        draft.name = "Original activity"; draft.addressName = "Original venue"
        draft.description = "Original description"; draft.coverURL = "fixture://cover"
        draft.start = "2030-01-01 09:00"; draft.end = "2030-01-01 18:00"
        draft.categoryIDs = [3]; draft.playTemplateID = AuthoringPlayTemplateID(rawValue: 41)
        var ticket = ActivityPublishTicket()
        ticket.name = "Original ticket"; ticket.price = "0"; ticket.stock = "10"
        ticket.start = draft.start; ticket.end = draft.end
        var secondTicket = ticket; secondTicket.id = UUID()
        draft.tickets = [ticket, secondTicket]
        return draft
    }

    func testEveryActualCoreReasonResolvesWithoutChangingDraftOrWireAcceptance() throws {
        let cases: [(Int, String, (inout ActivityPublishDraft) -> Void)] = [
            (0, "name", { $0.name = " " }),
            (0, "addressName", { $0.addressName = "" }),
            (0, "startDate", { $0.start = "not a date" }),
            (0, "endDate", { $0.end = "not a date" }),
            (0, "endDate", { $0.end = $0.start }),
            (0, "categoryIds", { $0.categoryIDs = [] }),
            (0, "categoryIds", { $0.categoryIDs = [0] }),
            (1, "description", { $0.description = "\n" }),
            (1, "templateId", { $0.playTemplateID = nil }),
            (1, "imgUrl", { $0.coverURL = "" }),
            (2, "collaborators", { $0.collaboratorMemberIDs = [0] }),
            (2, "collaborators", { $0.collaboratorMemberIDs = [7, 7] }),
            (2, "ticket", { $0.tickets = [] }),
            (2, "startDate", { $0.start = "invalid" }),
            (2, "ticketName1", { $0.tickets[1].name = "" }),
            (2, "ticketPrice1", { $0.tickets[1].price = "-1" }),
            (2, "ticketPrice1", { $0.tickets[1].price = "invalid" }),
            (2, "ticketStock1", { $0.tickets[1].stock = "0" }),
            (2, "ticketStart1", { $0.tickets[1].start = "invalid" }),
            (2, "ticketEnd1", { $0.tickets[1].end = "invalid" }),
            (2, "ticketEnd1", { $0.tickets[1].end = $0.tickets[1].start }),
            (2, "ticketEnd1", { $0.tickets[1].start = "2030-01-01 08:59" }),
            (2, "ticketEnd1", { $0.tickets[1].end = "2030-01-01 18:01" })
        ]
        for (step, expected, change) in cases {
            var draft = readyDraft(); change(&draft)
            let original = draft
            XCTAssertEqual(ActivityPublishingWizard.blockingField(step, draft), expected)
            XCTAssertThrowsError(try draft.wire())
            for language in ["en", "zh-Hans"] {
                let model = presentation(language)
                let message = model.message(for: ActivityPublishingWizard.blockingField(step, draft))
                XCTAssertEqual(message, model.message(for: expected))
                XCTAssertNotEqual(message, model.message(for: "futureField"))
            }
            XCTAssertEqual(draft, original)
            XCTAssertThrowsError(try draft.wire())
        }
    }

    func testNormalWizardForwardBackRestoreAndFinalReviewKeepOriginalSemantics() throws {
        var draft = ActivityPublishDraft()
        XCTAssertEqual(ActivityPublishingWizard.blockingField(0, draft), "name")
        let ready = readyDraft()
        draft.name = ready.name; draft.addressName = ready.addressName
        draft.start = ready.start; draft.end = ready.end; draft.categoryIDs = ready.categoryIDs
        XCTAssertEqual(ActivityPublishingWizard.advance(from: 0, draft: draft), 1)
        XCTAssertEqual(ActivityPublishingWizard.blockingField(1, draft), "description")
        draft.description = ready.description; draft.coverURL = ready.coverURL; draft.playTemplateID = ready.playTemplateID
        XCTAssertEqual(ActivityPublishingWizard.advance(from: 1, draft: draft), 2)
        XCTAssertEqual(ActivityPublishingWizard.blockingField(2, draft), "ticket")
        draft.tickets = ready.tickets
        let original = draft, wire = try draft.wire()
        XCTAssertEqual(ActivityPublishingWizard.retreat(from: 2), 1)
        XCTAssertEqual(ActivityPublishingWizard.advance(from: 1, draft: draft), 2)
        XCTAssertEqual(ActivityPublishingWizard.located(99, draft: draft), 2)
        for step in 0...2 {
            XCTAssertNil(ActivityPublishingWizard.blockingField(step, draft))
            for language in ["en", "zh-Hans"] {
                _ = presentation(language).message(for: ActivityPublishingWizard.blockingField(step, draft))
            }
        }
        XCTAssertTrue(ActivityPublishingWizard.acceptsReview(draft))
        XCTAssertEqual(draft, original); XCTAssertEqual(try draft.wire(), wire)
        draft.name = ""
        XCTAssertFalse(ActivityPublishingWizard.acceptsReview(draft))
        XCTAssertEqual(ActivityPublishingWizard.located(99, draft: draft), 0)
        XCTAssertEqual(ActivityPublishingWizard.blockingField(0, draft), "name")
    }
}
