import Foundation
import XCTest
@testable import Questify

final class NativeRpgGrowthAuthorValidationTests: XCTestCase {
    private func editor(role: Bool = true) throws -> NativeRpgGrowthAuthorDraft {
        var draft = try NativeRpgGrowthAuthorDraft(original: .string("{\"schemaVersion\":2,\"role\":{\"enabled\":\(role)}}"))
        draft.useFormalCurve()
        return draft
    }
    func testValidCurveRemainsPreviewableWithoutMutation() throws {
        let draft = try editor(), before = draft
        let check = NativeRpgGrowthAuthorValidation(draft)
        XCTAssertTrue(check.canPreview); XCTAssertTrue(check.issues.isEmpty)
        XCTAssertEqual(check.thresholdCount, 9); XCTAssertEqual(check.requiredThresholdCount, 9)
        XCTAssertEqual(draft, before)
    }
    func testOriginalUnchangedUnknownConfigurationKeepsBytePassthrough() throws {
        let raw = "{ \"schemaVersion\":2, \"growth\":{\"future\":\"é\"} }"
        let draft = try NativeRpgGrowthAuthorDraft(original: .string(raw))
        let check = NativeRpgGrowthAuthorValidation(draft)
        XCTAssertTrue(check.canPreview); XCTAssertTrue(check.issues.isEmpty)
        XCTAssertEqual(Array(try XCTUnwrap(draft.serialized().text).utf8), Array(raw.utf8))
    }
    func testCountMismatchCanBeRepairedWithOriginalControls() throws {
        var draft = try editor()
        draft.set("maxLevel", .number(9))
        XCTAssertEqual(NativeRpgGrowthAuthorValidation(draft).issues, [.thresholdCount])
        draft.removeLastThreshold()
        XCTAssertTrue(NativeRpgGrowthAuthorValidation(draft).canPreview)
    }
    func testThresholdActionsRespectZeroAndNineteenBoundaries() throws {
        var draft = try editor()
        draft.set("xpThresholds", .array([]))
        XCTAssertFalse(NativeRpgGrowthAuthorValidation(draft).canRemoveThreshold)
        XCTAssertTrue(NativeRpgGrowthAuthorValidation(draft).canAddThreshold)
        draft.set("xpThresholds", .array((1...19).map { .number(Decimal($0)) }))
        XCTAssertFalse(NativeRpgGrowthAuthorValidation(draft).canAddThreshold)
        XCTAssertTrue(NativeRpgGrowthAuthorValidation(draft).canRemoveThreshold)
    }
    func testOriginalPermissionAndNumericRejectionsHaveSpecificReasons() throws {
        var draft = try editor(role: false)
        draft.set("enabled", .bool(true))
        draft.set("skillPointsPerLevel", .string("bad"))
        draft.threshold(1, value: "100")
        let check = NativeRpgGrowthAuthorValidation(draft)
        XCTAssertTrue(check.issues.contains(.role)); XCTAssertTrue(check.issues.contains(.skillPoints)); XCTAssertTrue(check.issues.contains(.thresholdOrder))
        XCTAssertFalse(check.canPreview); XCTAssertThrowsError(try draft.serialized())
        XCTAssertFalse(draft.roleEnabled)
    }
    func testUnknownAndDuplicateFeatsAreNotSilentlyRemoved() throws {
        var draft = try editor()
        draft.set("feats", .array([.string("unknown"), .string("unknown")]))
        let before = draft
        XCTAssertTrue(NativeRpgGrowthAuthorValidation(draft).issues.contains(.feats))
        XCTAssertEqual(draft, before)
    }
}
