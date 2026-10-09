import XCTest
@testable import QuestifyCore

final class MerchantInsightInterpretationTests: XCTestCase {
    private func insight(_ ai: MerchantMarketingValue) throws -> MerchantMarketingInsight {
        try .init(.object(["facts": .object([:]), "ai": ai]))
    }
    func testExactOpportunityAndProblemTextIsPreserved() throws {
        let result = try insight(.object(["opportunity": .string("  Exact opportunity\n"), "problem": .string("Exact concern")]))
        XCTAssertEqual(result.opportunity, "  Exact opportunity\n"); XCTAssertEqual(result.problem, "Exact concern")
    }
    func testMissingOrUnavailableAIHasNoInventedInterpretation() throws {
        for ai in [MerchantMarketingValue.null, .array([]), .string("advice"), .object([:])] {
            let result = try insight(ai); XCTAssertNil(result.opportunity); XCTAssertNil(result.problem)
        }
    }
    func testOnlyActualNonblankStringsCanBecomeInterpretation() throws {
        for value in [MerchantMarketingValue.null, .number(7), .bool(true), .array([]), .object([:]), .string(" \n ")] {
            let result = try insight(.object(["opportunity": value, "problem": value]))
            XCTAssertNil(result.opportunity); XCTAssertNil(result.problem)
        }
    }
    func testTextContainingRoutesDoesNotCreateANavigationSuggestion() throws {
        let raw = "Open https://example.test/path or /merchant/decor"
        let result = try insight(.object(["opportunity": .string(raw), "problem": .string(raw)]))
        XCTAssertEqual(result.opportunity, raw); XCTAssertEqual(result.problem, raw)
        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertNil(MerchantInsightDestination(rawValue: raw))
    }
}
