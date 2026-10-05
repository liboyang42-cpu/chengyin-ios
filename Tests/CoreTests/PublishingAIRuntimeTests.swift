import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PublishingAIRuntimeTests: XCTestCase {
    private let base = URL(string: "https://example.com/scoped/")!
    private func request(_ fields: [String: ProjectEditJSON], path: String = "api/ai/theme/draft") throws -> URLRequest {
        try OperationAdapterHTTP.json(configuration: APIConfiguration(baseURL: base), path: path, body: JSONEncoder().encode(fields), token: "synthetic")
    }
    func testFeatureCatalogKeepsAISeparateFromPublishingWrites() throws {
        let theme = try BusinessRuntimeRoute.post("api/ai/theme/draft")
        XCTAssertTrue(BusinessRuntimeFeature.publishingAITheme.accepts(theme))
        XCTAssertFalse(BusinessRuntimeFeature.publishingWrite.accepts(theme))
        XCTAssertFalse(BusinessRuntimeFeature.publishingAIClub.accepts(theme))
        XCTAssertFalse(BusinessRuntimeFeature.publishingAITheme.accepts(try .init(method: "GET", path: theme.path)))
    }
    func testExactThemeBodyRejectsMissingModeOrExtraFields() throws {
        let fields: [String: ProjectEditJSON] = ["idea": .string("Synthetic route"), "productType": .number(2)]
        XCTAssertTrue(PublishingAIRuntimeTransport.validates(try request(fields), feature: .publishingAITheme, baseURL: base))
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(["idea": .string("Walk")]), feature: .publishingAITheme, baseURL: base))
        var extra = fields; extra["ownerId"] = .number(1)
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(extra), feature: .publishingAITheme, baseURL: base))
        extra = fields; extra["productType"] = .number(9)
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(extra), feature: .publishingAITheme, baseURL: base))
    }
    func testClubOptionalFieldsRemainSourceTyped() throws {
        let fields: [String: ProjectEditJSON] = ["idea": .string("Synthetic route"), "clubStyle": .string("walking"), "targetDurationMin": .number(60)]
        XCTAssertTrue(PublishingAIRuntimeTransport.validates(try request(fields, path: "api/ai/club/design"), feature: .publishingAIClub, baseURL: base))
        var extra = fields; extra["productType"] = .number(2)
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(extra, path: "api/ai/club/design"), feature: .publishingAIClub, baseURL: base))
    }
    func testQuotaCannotCarryPromptOrQuery() throws {
        var request = URLRequest(url: base.appendingPathComponent("api/ai/theme/draft/quota")); request.httpMethod = "POST"
        XCTAssertTrue(PublishingAIRuntimeTransport.validates(request, feature: .publishingAIQuota, baseURL: base))
        request.httpBody = Data("{}".utf8)
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(request, feature: .publishingAIQuota, baseURL: base))
        request.httpBody = nil; request.url = URL(string: base.absoluteString + "api/ai/theme/draft/quota?prompt=unexpected")
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(request, feature: .publishingAIQuota, baseURL: base))
    }
    func testWrongOriginMethodAndUnknownProviderRouteAreRejected() throws {
        var input = try request(["idea": .string("Walk"), "productType": .number(1)])
        input.httpMethod = "GET"; XCTAssertFalse(PublishingAIRuntimeTransport.validates(input, feature: .publishingAITheme, baseURL: base))
        input.httpMethod = "POST"; input.url = URL(string: "https://example.com/other/api/ai/theme/draft")
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(input, feature: .publishingAITheme, baseURL: base))
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request([:]), feature: .projectWrite, baseURL: base))
    }
}
