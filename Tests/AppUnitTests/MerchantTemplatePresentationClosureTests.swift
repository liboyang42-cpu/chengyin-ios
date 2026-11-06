import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Presentation/resource closure only. No live reader, authoring grant or mutation.
@MainActor final class MerchantTemplatePresentationClosureTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func source(_ name: String) throws -> String {
        try String(contentsOf: sourceRoot.appendingPathComponent("App/" + name), encoding: .utf8)
    }
    func testOriginalTextAndAbsentValueAreNotRewritten() {
        XCTAssertEqual(MerchantCreationOriginalValue.display(.string("  Original\n")), "  Original\n")
        XCTAssertEqual(MerchantCreationOriginalValue.display(nil), "")
    }
    func testOriginalNumbersArraysObjectsBooleansAndNullRoundTrip() throws {
        for json in [#"4"#, #"["RAIN","INDOOR"]"#, #"{"z":2,"a":1}"#, #"true"#, #"null"#] {
            let original = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(json.utf8))
            let displayed = MerchantCreationOriginalValue.display(original)
            XCTAssertFalse(displayed.isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(ProjectEditJSON.self, from: Data(displayed.utf8)), original)
        }
    }
    func testOriginalObjectDisplayIsStableAndSorted() throws {
        let original = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(#"{"z":2,"a":1}"#.utf8))
        let first = MerchantCreationOriginalValue.display(original)
        XCTAssertEqual(first, MerchantCreationOriginalValue.display(original))
        XCTAssertLessThan(try XCTUnwrap(first.range(of: "\"a\"" )).lowerBound,
                          try XCTUnwrap(first.range(of: "\"z\"" )).lowerBound)
    }
    func testKnownAndUnknownLabelsUseExistingKeysWithoutInferringSuccess() {
        XCTAssertEqual(MerchantAuthoringLabels.field("canonical_plot"), "merchantAuthoring.plot")
        XCTAssertEqual(MerchantAuthoringLabels.field("unexpected"), "merchantAuthoring.otherField")
        XCTAssertEqual(MerchantAuthoringLabels.environmentReason("unexpected"), "merchantAuthoring.environment.reason.ENVIRONMENT_UNAVAILABLE")
        XCTAssertNil(MerchantAuthoringLabels.generationFailure("unexpected"))
    }
    func testOriginalCatalogHasAll273CompleteBilingualEntries() throws {
        let data = try Data(contentsOf: sourceRoot.appendingPathComponent("Resources/MerchantAuthoring.xcstrings"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        XCTAssertEqual(strings.count, 273)
        for (key, entry) in strings {
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
            for language in ["en", "zh-Hans"] {
                let unit = try XCTUnwrap(localizations[language]?["stringUnit"] as? [String: Any])
                XCTAssertFalse(try XCTUnwrap(unit["value"] as? String).isEmpty, key)
            }
        }
    }
    func testAuthoringCatalogCompilesToTheHelpersNamedBundleTable() throws {
        for (language, expected) in [("en", "Retry"), ("zh-Hans", "重试")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "merchantAuthoring.retry", value: nil, table: "MerchantAuthoring"), expected)
        }
    }
    func testTemplateReadersSelectionAndSaveGatesRemainTheOriginalOnes() throws {
        let browser = try source("MerchantTemplateBrowserView.swift")
        XCTAssertTrue(browser.contains("model.open(row.id, permit: permit)"))
        XCTAssertTrue(browser.contains(".disabled(!browser.canOpen)"))
        XCTAssertTrue(browser.contains(".disabled(!browser.canLoadMore)"))
        XCTAssertTrue(browser.contains("QuestifyCardArtwork.safeURL(imageSource)"))
        XCTAssertTrue(browser.contains("ObjectCardBoundedImageLoader(policy: .init(approvedOrigins: [origin]))"))
        let suggestion = try source("MerchantTemplateSuggestionEditSheet.swift")
        XCTAssertTrue(suggestion.contains("Binding(get: { model.edit?.text ?? \"\" }, set: model.update)"))
        XCTAssertTrue(suggestion.contains("if model.save() { dismiss() }"))
        XCTAssertTrue(suggestion.contains(".disabled(!model.canSave)"))
        XCTAssertFalse(browser.contains("URLSession")); XCTAssertFalse(suggestion.contains("confirmPublish"))
    }
    func testOptInFieldAndNoticeRenderAtAccessibilitySizeInBothLocales() {
        for locale in ["en", "zh-Hans"] {
            let view = Form {
                TextField("Existing field", text: .constant("Original draft value with a long visible label"))
                    .merchantCreationFieldLabel(Text("Existing visible field label"))
                merchantCreationNotice(merchantAuthoringText("merchantAuthoring.otherField"))
                merchantCreationLabeled("merchantAuthoring.publicVersion", value: "Original revision 123456789")
            }.merchantCreationSurface().environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, .accessibility5)
            let host = UIHostingController(rootView: view)
            host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            XCTAssertNotNil(host.view)
        }
    }
}
