import XCTest
@testable import QuestifyCore

final class TemplateSensorRehearsalTests: XCTestCase {
    private func draft(_ game: TemplateAdvancedGame) -> TemplateAdvancedDraft {
        var d = TemplateAdvancedDraft(); d.setGameEnabled(game, true)
        if game == .compass { d.set("compass", "bearing", .number(0)) }
        return d
    }
    private func make(_ game: TemplateAdvancedGame = .compass) throws -> TemplateSensorRehearsal {
        try XCTUnwrap(TemplateSensorRehearsal(draft(game), game: game))
    }
    func testOnlyValidEnabledSensorDraftsCanRehearse() throws {
        XCTAssertNil(TemplateSensorRehearsal(TemplateAdvancedDraft(), game: .compass))
        XCTAssertNil(TemplateSensorRehearsal(draft(.sort), game: .sort))
        var invalid = draft(.compass); invalid.set("compass", "bearing", .number(360))
        XCTAssertNil(TemplateSensorRehearsal(invalid, game: .compass))
        XCTAssertEqual(try make(.shout).feedback, .ready)
    }
    func testCompassNeedsContinuousAlignedVirtualInput() throws {
        var state = try make()
        state.advance(bearing: 180, accuracy: 0, peak: 0.1)
        XCTAssertEqual(state.feedback, .turn); XCTAssertEqual(state.heldSeconds, 0)
        state.advance(bearing: 0, accuracy: 0, peak: 0.1)
        XCTAssertEqual(state.feedback, .aligned); XCTAssertFalse(state.finished)
        for _ in 0..<4 { state.advance(bearing: 0, accuracy: 0, peak: 0.1) }
        XCTAssertEqual(state.feedback, .matched)
        XCTAssertEqual(state.heldSeconds, state.duration)
    }
    func testPoorAccuracyAndDirectionChangeClearHold() throws {
        var state = try make()
        state.advance(bearing: 0, accuracy: 0, peak: 0.1)
        XCTAssertGreaterThan(state.heldSeconds, 0)
        state.advance(bearing: 0, accuracy: 180, peak: 0.1)
        XCTAssertEqual(state.feedback, .inaccurate); XCTAssertEqual(state.heldSeconds, 0)
        state.advance(bearing: 0, accuracy: 0, peak: 0.1)
        state.advance(bearing: 180, accuracy: 0, peak: 0.1)
        XCTAssertEqual(state.heldSeconds, 0)
    }
    func testCompassNorthWrapUsesExistingAngularRules() throws {
        var state = try make()
        state.advance(bearing: 359, accuracy: 0, peak: 0.1)
        XCTAssertEqual(state.feedback, .aligned)
    }
    func testShoutVirtualBaselineAndQuietReset() throws {
        var state = try make(.shout)
        XCTAssertEqual(state.loudThreshold, 0.25, accuracy: 0.0001)
        state.advance(bearing: 0, accuracy: 0, peak: 1)
        XCTAssertGreaterThan(state.heldSeconds, 0)
        state.advance(bearing: 0, accuracy: 0, peak: 0.1)
        XCTAssertEqual(state.feedback, .quiet); XCTAssertEqual(state.heldSeconds, 0)
        for _ in 0..<7 { state.advance(bearing: 0, accuracy: 0, peak: 1) }
        XCTAssertEqual(state.feedback, .matched)
    }
    func testInvalidVirtualInputDoesNotAdvance() throws {
        var state = try make(), baseline = state
        XCTAssertFalse(state.advance(bearing: .nan, accuracy: 0, peak: 0.1)); XCTAssertEqual(state, baseline)
        XCTAssertFalse(state.advance(bearing: 0, accuracy: -1, peak: 0.1)); XCTAssertEqual(state, baseline)
        XCTAssertFalse(state.advance(bearing: 0, accuracy: 0, peak: 2)); XCTAssertEqual(state, baseline)
        baseline.reset(); XCTAssertEqual(state, baseline)
    }
    func testFinishedAttemptRequiresResetAndOriginalDraftNeverChanges() throws {
        let original = draft(.compass), before = original
        var state = try XCTUnwrap(TemplateSensorRehearsal(original, game: .compass))
        for _ in 0..<5 { state.advance(bearing: 0, accuracy: 0, peak: 0.1) }
        let done = state
        XCTAssertFalse(state.advance(bearing: 180, accuracy: 0, peak: 0.1)); XCTAssertEqual(state, done)
        state.reset(); XCTAssertEqual(state.feedback, .ready); XCTAssertEqual(state.heldSeconds, 0)
        XCTAssertEqual(original, before)
    }
}
