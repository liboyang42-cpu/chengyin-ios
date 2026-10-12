import XCTest
@testable import QuestifyCore

final class TemplatePhotoFrameConfigurationTests: XCTestCase {
    private func fixture(_ reference: String = "https://example.invalid/frame.png", opacity: Double = 40) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.photoCheck, true); draft.set("photoCheck", "title", .string("Frame the window")); draft.set("photoCheck", "requirement", .string("Window in frame")); draft.set("photoCheck", "frameUrl", .string(reference)); draft.set("photoCheck", "frameOpacity", .number(opacity)); return draft
    }
    func testOpeningPreservesStoredReferenceAndNonStepOpacity() {
        let draft = fixture("/frames/outline.png", opacity: 37), before = draft, config = TemplatePhotoFrameConfiguration(draft)
        XCTAssertTrue(config.isSupported); XCTAssertEqual(config.reference, "/frames/outline.png"); XCTAssertEqual(config.opacity, 37); XCTAssertNil(config.previewURL); XCTAssertEqual(draft, before)
    }
    func testAbsoluteHTTPSPreviewAllowsAddressWithoutModifyingDraft() {
        let draft = fixture(), config = TemplatePhotoFrameConfiguration(draft)
        XCTAssertEqual(config.previewURL?.absoluteString, "https://example.invalid/frame.png"); XCTAssertTrue(config.canClear); XCTAssertTrue(config.canAdjustOpacity)
    }
    func testPreviewRejectsRelativeInsecureCredentialFragmentAndControlAddresses() {
        for value in ["", "/frames/f.png", "http://example.invalid/f.png", "https://name:secret@example.invalid/f.png", "https://example.invalid/f.png#part", "https://example.invalid/f.png\n", " https://example.invalid/f.png", "https://example.invalid/a\\b", "data:image/png;base64,xx", "https://example.invalid/" + String(repeating: "a", count: 513)] {
            let draft = fixture(value), config = TemplatePhotoFrameConfiguration(draft); XCTAssertNil(config.previewURL, value); XCTAssertEqual(config.reference, value)
        }
    }
    func testEditReferenceOpacityAndClearChangeOnlyTheirExistingFields() throws {
        var draft = fixture(); let original = draft
        draft = try XCTUnwrap(TemplatePhotoFrameConfiguration(draft).applying(.reference("/frames/new.png"), to: draft))
        XCTAssertEqual(draft.value["photoCheck"]?.object?["frameOpacity"], .number(40))
        draft = try XCTUnwrap(TemplatePhotoFrameConfiguration(draft).applying(.opacity(65), to: draft)); XCTAssertEqual(draft.text("photoCheck", "frameUrl"), "/frames/new.png")
        draft = try XCTUnwrap(TemplatePhotoFrameConfiguration(draft).applying(.clear, to: draft)); XCTAssertEqual(draft.value["photoCheck"]?.object?["frameUrl"], .string("")); XCTAssertEqual(draft.value["photoCheck"]?.object?["frameOpacity"], .number(65))
        for key in ["title", "requirement", "shotNote", "minConfidence", "maxTries", "fallback", "xp", "mode", "cardTitle", "cardStyle"] { XCTAssertEqual(draft.value["photoCheck"]?.object?[key], original.value["photoCheck"]?.object?[key]) }
    }
    func testSliderRangeHasZeroAndHundredWithoutClampingInvalidValues() throws {
        var draft = fixture()
        for value in [0.0, 5, 35, 100] { draft = try XCTUnwrap(TemplatePhotoFrameConfiguration(draft).applying(.opacity(value), to: draft)); XCTAssertEqual(TemplatePhotoFrameConfiguration(draft).opacity, value) }
        for value in [-1.0, 101, 3.5, .infinity, .nan] { XCTAssertNil(TemplatePhotoFrameConfiguration(draft).applying(.opacity(value), to: draft)) }
    }
    func testEmptyReferenceHidesAdjustmentAndDoesNotCreateClearWrites() {
        let draft = fixture(""), config = TemplatePhotoFrameConfiguration(draft)
        XCTAssertTrue(config.isSupported); XCTAssertFalse(config.canAdjustOpacity); XCTAssertFalse(config.canClear); XCTAssertNil(config.applying(.clear, to: draft)); XCTAssertNil(config.applying(.opacity(50), to: draft))
    }
    func testMissingOptionalFieldsReadNativeDefaultWithoutInitializingThem() {
        var draft = fixture(); draft.setCreatorValue(.photoCheck, path: [.field("frameUrl")], entry: nil); draft.setCreatorValue(.photoCheck, path: [.field("frameOpacity")], entry: nil)
        let before = draft, config = TemplatePhotoFrameConfiguration(draft); XCTAssertTrue(config.isSupported); XCTAssertEqual(config.reference, ""); XCTAssertEqual(config.opacity, 40); XCTAssertEqual(draft, before)
    }
    func testMalformedStoredShapesKeepGenericFallback() {
        for value in [TemplateAuthoringJSON.string("bad"), .number(-1), .number(101), .number(1.5), .object([:])] {
            var draft = fixture(); draft.set("photoCheck", "frameOpacity", value); let before = draft, config = TemplatePhotoFrameConfiguration(draft)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(.clear, to: draft)); XCTAssertEqual(draft, before)
        }
        var draft = fixture(); draft.set("photoCheck", "frameUrl", .number(1)); XCTAssertFalse(TemplatePhotoFrameConfiguration(draft).isSupported)
    }
    func testDisabledFamilyAndStaleScopeRejectEdits() {
        let draft = fixture(), config = TemplatePhotoFrameConfiguration(draft); var changed = draft
        changed.set("photoCheck", "title", .string("Other")); XCTAssertFalse(config.isCurrent(changed)); XCTAssertNil(config.applying(.clear, to: changed))
        changed = draft; changed.setCreatorEnabled(.photoCheck, false); XCTAssertFalse(TemplatePhotoFrameConfiguration(changed).canEdit)
    }
    func testUnknownFieldsAndOtherFamiliesArePreserved() throws {
        var draft = fixture(); draft.set("photoCheck", "future", .string("keep")); draft.set("timer", "enabled", .bool(true)); let before = draft
        let next = try XCTUnwrap(TemplatePhotoFrameConfiguration(draft).applying(.opacity(75), to: draft))
        XCTAssertEqual(next.value["photoCheck"]?.object?["future"], .string("keep")); XCTAssertEqual(next.value["timer"], before.value["timer"])
    }
    func testExistingNormalizationRemovesClearedOptionalFrameFieldsOnlyAtSerialize() throws {
        let draft = fixture(opacity: 65), cleared = try XCTUnwrap(TemplatePhotoFrameConfiguration(draft).applying(.clear, to: draft))
        XCTAssertEqual(cleared.value["photoCheck"]?.object?["frameOpacity"], .number(65)); XCTAssertTrue(cleared.creatorIssues(.photoCheck).isEmpty)
        let raw = try cleared.serialize(), object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], photo = object?["photoCheck"] as? [String: Any]
        XCTAssertNil(photo?["frameUrl"]); XCTAssertNil(photo?["frameOpacity"])
    }
    func testLocalDraftRoundTripRetainsAddressAndOpacityWithoutFetchingImage() throws {
        var local = TemplateAuthoringDraft(title: "Frame"); local.advanced = fixture("/frames/outline.png", opacity: 75)
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)); XCTAssertEqual(restored, local)
        let config = TemplatePhotoFrameConfiguration(restored.advanced); XCTAssertEqual(config.reference, "/frames/outline.png"); XCTAssertEqual(config.opacity, 75); XCTAssertNil(config.previewURL)
    }
}
