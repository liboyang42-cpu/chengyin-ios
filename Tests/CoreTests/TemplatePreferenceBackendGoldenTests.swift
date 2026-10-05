import Foundation
import XCTest
@testable import QuestifyCore

/// Fixtures were executed by the real Java evaluator; native parity is established only when this XCTest runs.
final class TemplatePreferenceBackendGoldenTests: XCTestCase {
    private struct Golden: Decodable {
        let name: String
        let raw: String?
        let backendValid: Bool
        let nativeStatus: String
        let workLimit: Int?
    }
    func testNativeValidationAgainstRealBackendGoldens() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TemplatePreference/goldens.json")
        let cases = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 142)
        for item in cases {
            // A nil optional draft source enters the editor as an empty string; neither represents a valid root.
            let check = TemplatePreferenceDraftCheck.inspect(item.raw ?? "", workLimit: item.workLimit ?? 1_000_000)
            XCTAssertEqual(check.status.rawValue, item.nativeStatus, item.name)
            if check.status == .valid { XCTAssertTrue(item.backendValid, item.name) }
            if check.status == .invalid { XCTAssertFalse(item.backendValid, item.name) }
            if !check.canPreview { XCTAssertTrue(check.fields.isEmpty, item.name) }
        }
    }
}
