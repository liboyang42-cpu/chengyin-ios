import XCTest
@testable import Questify

@MainActor final class ApprovedTopicReviewRouteBudgetTests: XCTestCase {
    private let base = URL(string: "https://example.com/native")!
    private func fixture(_ name: String, _ part: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReviewRequestBudget/\(name)-\(part).json")
        return try Data(contentsOf: url)
    }
    private func route(_ path: String, _ bytes: Data) -> ApprovedReleaseCompositionRoute? {
        var request = URLRequest(url: base.appendingPathComponent(path)); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = bytes
        return .init(request: request, baseURL: base)
    }
    private func padded(_ bytes: Data, to count: Int) -> Data {
        bytes + Data(repeating: 32, count: count - bytes.count)
    }
    func testNineSourcePrepareVersusSubmitAndThirtyTwoSourcesReachDistinctRoutes() throws {
        for name in ["nine_prepare_fits_submit_does_not", "eleven_small_ids", "thirty_two_native_maximum"] {
            XCTAssertEqual(route(ApprovedTopicReviewPath.prepare, try fixture(name, "prepare")), .reviewPrepare)
            XCTAssertEqual(route(ApprovedTopicReviewPath.submit, try fixture(name, "submit")), .reviewSubmit)
        }
    }
    func testReviewSourceRoutesAcceptExactlySixteenKiBAndRejectOneByteMore() throws {
        for (part, path, expected) in [("prepare", ApprovedTopicReviewPath.prepare, ApprovedReleaseCompositionRoute.reviewPrepare),
                                       ("submit", ApprovedTopicReviewPath.submit, ApprovedReleaseCompositionRoute.reviewSubmit)] {
            let value = try fixture("thirty_two_native_maximum", part)
            XCTAssertEqual(route(path, padded(value, to: 16384)), expected)
            XCTAssertNil(route(path, padded(value, to: 16385)))
            XCTAssertNil(route(path, padded(value, to: 1024 * 1024)))
        }
    }
    func testSourcesAndSixFieldRecoverySelectorsRetainOriginalFourKiBCap() throws {
        let submit = try JSONDecoder().decode([String: ProjectEditJSON].self, from: fixture("thirty_two_native_maximum", "submit"))
        let selector = submit.filter { $0.key != "sourceSelections" }
        let sourceFields = submit.filter { $0.key == "topicId" || $0.key == "observedAuditTaskId" }
        for (path, fields, expected) in [(ApprovedTopicReviewPath.prepare, sourceFields, ApprovedReleaseCompositionRoute.reviewPrepare),
                                         (ApprovedTopicReviewPath.submit, selector, ApprovedReleaseCompositionRoute.reviewSubmit),
                                         (ApprovedTopicReviewPath.sources, sourceFields, ApprovedReleaseCompositionRoute.reviewSources),
                                         (ApprovedTopicReviewPath.status, selector, ApprovedReleaseCompositionRoute.reviewStatus),
                                         (ApprovedTopicReviewPath.current, selector, ApprovedReleaseCompositionRoute.reviewCurrent)] {
            let bytes = try JSONEncoder().encode(fields)
            XCTAssertEqual(route(path, padded(bytes, to: 4096)), expected)
            XCTAssertNil(route(path, padded(bytes, to: 4097)))
        }
    }
    func testThirtyThirdSelectionAndUnknownFieldsRejectEvenBelowByteLimit() throws {
        var fields = try JSONDecoder().decode([String: ProjectEditJSON].self, from: fixture("thirty_two_native_maximum", "submit"))
        guard case .array(var values)? = fields["sourceSelections"] else { return XCTFail() }
        values.append(try XCTUnwrap(values.first)); fields["sourceSelections"] = .array(values)
        let body = try JSONEncoder().encode(fields); XCTAssertLessThan(body.count, 16384)
        XCTAssertNil(route(ApprovedTopicReviewPath.submit, body))
        fields = try JSONDecoder().decode([String: ProjectEditJSON].self, from: fixture("eleven_small_ids", "prepare"))
        fields["publicationAuthority"] = .bool(true)
        XCTAssertNil(route(ApprovedTopicReviewPath.prepare, try JSONEncoder().encode(fields)))
    }
    func testLargerAllowanceDoesNotExpandUnrelatedPublishOrDraftRoutes() throws {
        let body = try fixture("thirty_two_native_maximum", "submit")
        for path in [ApprovedTopicReleasePaths.prepare, ApprovedTopicReleasePublicationPath.publish,
                     ApprovedTopicReleasePublicationPath.status, ProjectMerchantDraftPath.list, ProjectMerchantDraftPath.resolve] {
            XCTAssertNil(route(path, body))
        }
        XCTAssertNil(route("api/approved-topic-release/v1/review/submit/extra", body))
        XCTAssertNil(route(ApprovedTopicReviewPath.submit, Data("{".utf8) + Data(repeating: 91, count: 16384)))
    }
}
