import XCTest
@testable import QuestifyCore

final class TemplateScanResponseConfigurationTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.scan, true)
        for (key, value) in ["kind":"OVERLAY", "reply":"Hello", "audioUrl":"/voice.m4a", "imageUrl":"https://example.invalid/image.png", "overlayUrl":"https://example.invalid/overlay.png", "arMode":"MARKER", "markerUrl":"/marker.png", "modelUrl":"/model.glb"] { draft.set("scan", key, .string(value)) }
        draft.set("scan", "overlayScale", .number(60)); return draft
    }
    func testOpeningKeepsAllExistingBytesAndShowsCurrentFields() {
        let draft = fixture(), before = draft, config = TemplateScanResponseConfiguration(draft)
        XCTAssertTrue(config.isSupported); XCTAssertEqual(config.currentTextFields, [.reply, .overlayUrl, .markerUrl, .modelUrl]); XCTAssertEqual(config.retainedTextFields, [.audioUrl, .imageUrl]); XCTAssertEqual(draft, before)
    }
    func testModeSwitchChangesOnlyKindAndMakesRetainedARReachable() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.kind(.text), to: draft))
        var expected = draft; expected.set("scan", "kind", .string("TEXT")); XCTAssertEqual(next, expected)
        let config = TemplateScanResponseConfiguration(next); XCTAssertEqual(config.currentTextFields, [.reply]); XCTAssertTrue(config.showsRetainedAR); XCTAssertTrue(config.retainedTextFields.contains(.modelUrl)); XCTAssertTrue(config.retainedTextFields.contains(.markerUrl))
    }
    func testArSwitchDoesNotEraseRetainedModelOrMarkerAndClearIsExplicit() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.arMode(.none), to: draft))
        var expected = draft; expected.set("scan", "arMode", .string("NONE")); XCTAssertEqual(next, expected)
        let config = TemplateScanResponseConfiguration(next); XCTAssertEqual(config.retainedTextFields, [.audioUrl, .imageUrl, .markerUrl, .modelUrl]); XCTAssertTrue(config.canClearModel)
        let cleared = try XCTUnwrap(config.applying(.clearModel, to: next)); expected.set("scan", "modelUrl", .string("")); XCTAssertEqual(cleared, expected)
    }
    func testEveryTextFieldUsesExistingIndependentKey() throws {
        for field in TemplateScanResponseConfiguration.TextField.allCases {
            let draft = fixture(), next = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.text(field, "new value"), to: draft))
            var expected = draft; expected.set("scan", field.rawValue, .string("new value")); XCTAssertEqual(next, expected)
        }
    }
    func testOverlayScaleRangeAndImageWidthUseStoredConfiguration() throws {
        var draft = fixture(); draft.set("scan", "overlayScale", .number(37)); XCTAssertEqual(TemplateScanResponseConfiguration(draft).previewWidthPercent, 37)
        for value in [20.0, 25, 60, 100] { draft = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.scale(value), to: draft)); XCTAssertEqual(TemplateScanResponseConfiguration(draft).previewWidthPercent, value) }
        for value in [19.0, 101, 60.5, .infinity, .nan] { XCTAssertNil(TemplateScanResponseConfiguration(draft).applying(.scale(value), to: draft)) }
        draft = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.kind(.image), to: draft)); XCTAssertEqual(TemplateScanResponseConfiguration(draft).previewWidthPercent, 100); XCTAssertNil(TemplateScanResponseConfiguration(draft).applying(.scale(50), to: draft))
    }
    func testOnlyImageAndOverlayOfferPreviewWithoutFetch() throws {
        var draft = fixture(); XCTAssertEqual(TemplateScanResponseConfiguration(draft).previewURL?.absoluteString, "https://example.invalid/overlay.png")
        draft = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.kind(.image), to: draft)); XCTAssertEqual(TemplateScanResponseConfiguration(draft).previewURL?.absoluteString, "https://example.invalid/image.png")
        for kind in [TemplateScanResponseConfiguration.Kind.text, .voice] { draft = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.kind(kind), to: draft)); XCTAssertNil(TemplateScanResponseConfiguration(draft).previewReference); XCTAssertNil(TemplateScanResponseConfiguration(draft).previewURL) }
    }
    func testUntrustedOrRelativePreviewReferenceIsNotResolved() {
        for value in ["", "/overlay.png", "http://example.invalid/image.png", "https://u:p@example.invalid/a.png", "https://example.invalid/a.png#f", "https://example.invalid/a.png\n", "https://example.invalid/a\\b", "data:image/png;base64,x", "https://example.invalid/" + String(repeating: "x", count: 513)] {
            var draft = fixture(); draft.set("scan", "overlayUrl", .string(value)); let config = TemplateScanResponseConfiguration(draft); XCTAssertNil(config.previewURL, value); XCTAssertEqual(config.text(.overlayUrl), value); XCTAssertTrue(config.canEdit)
        }
    }
    func testMalformedShapeUsesGenericFallbackRatherThanNormalization() {
        for (field, value) in [("kind",TemplateAuthoringJSON.string("UNKNOWN")),("arMode",.number(2)),("overlayScale",.number(1e30)),("overlayScale",.string("bad")),("reply",.object([:]))] {
            var draft = fixture(); draft.set("scan", field, value); let before = draft, config = TemplateScanResponseConfiguration(draft)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(.clearModel, to: draft)); XCTAssertEqual(draft, before)
        }
    }
    func testInactiveConflictsRemainVisibleAndExistingValidatorOwnsResult() throws {
        var draft = fixture(); draft = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.kind(.text), to: draft)); XCTAssertFalse(draft.creatorIssues(.scan).isEmpty)
        var config = TemplateScanResponseConfiguration(draft); XCTAssertTrue(config.showsRetainedAR)
        draft = try XCTUnwrap(config.applying(.arMode(.none), to: draft)); config = .init(draft); XCTAssertTrue(config.retainedTextFields.contains(.modelUrl)); XCTAssertFalse(draft.creatorIssues(.scan).isEmpty)
        draft = try XCTUnwrap(config.applying(.clearModel, to: draft)); XCTAssertTrue(draft.creatorIssues(.scan).isEmpty)
    }
    func testStaleDisabledAndUnicodeChangedScopesRejectWrites() {
        var draft = fixture(); draft.set("scan", "reply", .string("\u{00E9}")); let config = TemplateScanResponseConfiguration(draft)
        draft.set("scan", "reply", .string("e\u{0301}")); XCTAssertFalse(config.isCurrent(draft)); XCTAssertNil(config.applying(.clearModel, to: draft))
        draft.setCreatorEnabled(.scan, false); XCTAssertFalse(TemplateScanResponseConfiguration(draft).canEdit)
    }
    func testUnknownFieldsOtherFamiliesAndXPRemainUnchanged() throws {
        var draft = fixture(); draft.set("scan", "future", .string("keep")); draft.set("scan", "xp", .number(88)); draft.set("timer", "enabled", .bool(true))
        let next = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.scale(75), to: draft)); XCTAssertEqual(next.value["timer"], draft.value["timer"]); XCTAssertEqual(next.value["scan"]?.object?["future"], .string("keep")); XCTAssertEqual(next.value["scan"]?.object?["xp"], .number(88))
    }
    func testClearSerializeAndExistingLocalRoundTrip() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateScanResponseConfiguration(draft).applying(.clearModel, to: draft)); XCTAssertEqual(next.text("scan", "modelUrl"), "")
        let raw = try next.serialize(), object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], scan = object?["scan"] as? [String: Any]; XCTAssertNil(scan?["modelUrl"])
        var local = TemplateAuthoringDraft(title: "Scan"); local.advanced = next; XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)), local)
    }
}
