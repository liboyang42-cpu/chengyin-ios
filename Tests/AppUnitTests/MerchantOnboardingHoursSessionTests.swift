import XCTest
@testable import Questify

@MainActor final class MerchantOnboardingHoursSessionTests: XCTestCase {
    private func harness(_ hours: String) async -> (MerchantOnboardingModel, MerchantOnboardingFixture) {
        let fixture = MerchantOnboardingFixture(name: "new")
        let model = MerchantOnboardingModel(coordinator: .init(server: fixture))
        model.reset(); await model.load()
        model.draft.name = "Original store"; model.draft.businessTime = hours
        return (model, fixture)
    }
    func testReopeningUsesCurrentWeekdaysAndOffStepMinutes() async throws {
        let (model, _) = await harness("周二、四 09:03-18:17")
        let editor = try XCTUnwrap(MerchantOnboardingHoursSession(model: model))
        XCTAssertEqual(editor.hours.days, [1, 3]); XCTAssertEqual(editor.hours.startMinutes, 543)
        XCTAssertEqual(editor.hours.endMinutes, 1097); XCTAssertFalse(editor.hasUnknownValue)
    }
    func testCancelPreservesOriginalByteSequenceAfterLocalEdits() async throws {
        let (model, fixture) = await harness("周三、一 09:03-18:17"); let before = model.draft
        let editor = try XCTUnwrap(MerchantOnboardingHoursSession(model: model))
        editor.edit { $0.days = [6]; $0.startMinutes = 0 }
        XCTAssertEqual(model.draft, before); editor.cancel(); XCTAssertFalse(editor.apply())
        XCTAssertEqual(model.draft, before); XCTAssertEqual(fixture.submissionCount, 0); XCTAssertEqual(fixture.uploadCount, 0)
    }
    func testNoOpApplyDoesNotNormalizeExistingDayOrderOrMinutes() async throws {
        let raw = "周三、一 09:03-18:17", (model, fixture) = await harness("周三、一 09:03-18:17")
        let editor = try XCTUnwrap(MerchantOnboardingHoursSession(model: model))
        XCTAssertTrue(editor.apply()); XCTAssertEqual(model.draft.businessTime, raw)
        XCTAssertFalse(editor.apply()); XCTAssertEqual(fixture.submissionCount, 0)
    }
    func testUnknownHistoricalFormatCannotApplyDefaultsWithoutExplicitEdit() async throws {
        let raw = "历史营业时间：节假日另行通知", (model, _) = await harness("历史营业时间：节假日另行通知")
        let editor = try XCTUnwrap(MerchantOnboardingHoursSession(model: model))
        XCTAssertTrue(editor.hasUnknownValue); XCTAssertFalse(editor.canApply); XCTAssertFalse(editor.apply())
        XCTAssertEqual(model.draft.businessTime, raw)
        editor.edit { $0.days = [0]; $0.startMinutes = 1200; $0.endMinutes = 120 }
        XCTAssertTrue(editor.apply()); XCTAssertEqual(model.draft.businessTime, "周一 20:00-次日02:00")
    }
    func testExplicitValidApplyChangesOnlyBusinessTimeAndMakesNoRequest() async throws {
        let (model, fixture) = await harness("周一 10:00-22:00"); var expected = model.draft
        let editor = try XCTUnwrap(MerchantOnboardingHoursSession(model: model))
        editor.edit { $0.days = [5, 6]; $0.startMinutes = 1200; $0.endMinutes = 120 }
        expected.businessTime = "周六、日 20:00-次日02:00"
        XCTAssertTrue(editor.apply()); XCTAssertEqual(model.draft, expected)
        XCTAssertEqual(fixture.submissionCount, 0); XCTAssertEqual(fixture.uploadCount, 0)
    }
    func testSourceReloadAccountChangeAndOtherDraftEditRejectStaleApply() async throws {
        let (model, fixture) = await harness("周一 10:00-22:00")
        let reloaded = try XCTUnwrap(MerchantOnboardingHoursSession(model: model)); await model.load(); XCTAssertFalse(reloaded.apply())
        let changed = try XCTUnwrap(MerchantOnboardingHoursSession(model: model)); model.draft.name = "Newer name"; XCTAssertFalse(changed.apply())
        let account = try XCTUnwrap(MerchantOnboardingHoursSession(model: model)); fixture.replaceAccount(); XCTAssertFalse(account.apply())
    }
    func testEmptyDraftUsesExplicitDefaultChoiceButRejectsZeroDuration() async throws {
        let (model, _) = await harness("")
        let editor = try XCTUnwrap(MerchantOnboardingHoursSession(model: model)); XCTAssertTrue(editor.canApply)
        editor.edit { $0.endMinutes = $0.startMinutes }; XCTAssertFalse(editor.canApply); XCTAssertFalse(editor.apply())
        XCTAssertEqual(model.draft.businessTime, "")
        editor.edit { $0.endMinutes = 1320 }; XCTAssertTrue(editor.apply())
        XCTAssertEqual(model.draft.businessTime, "周一至周日 10:00-22:00")
    }
}
