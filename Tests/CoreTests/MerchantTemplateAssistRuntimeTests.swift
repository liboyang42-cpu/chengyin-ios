import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class TemplateAssistTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var response = #"{"code":200,"data":{"template":{"questionAnswer":"Lantern"}}}"#
    var loseResponse = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if loseResponse { throw URLError(.networkConnectionLost) }
        return (Data(response.utf8), status)
    }
}
@MainActor private final class TemplateAssistJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = record }
    func clear(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = nil }
}
@MainActor final class MerchantTemplateAssistRuntimeTests: XCTestCase {
    private let base = URL(string: "https://example.test/scoped/")!
    private func service(_ transport: TemplateAssistTransport, journal: TemplateAssistJournal, approved: Bool = true, role: String = "merchant", region: PublishingRegion = .china) throws -> PublishingAuxiliaryService {
        let session = PublishingSession(namespace: "synthetic", accountID: 901, epoch: UUID(), role: role, region: region)
        let credential = try PublishingCredentials(session: session, token: "synthetic")
        let approval = try OperationEndpointApproval(baseURL: base, namespace: session.namespace, accountID: session.accountID, paths: ["api/ai/template/fill"])
        return PublishingAuxiliaryService(configuration: try .init(baseURL: base), transport: transport, approval: approved ? approval : nil, journal: journal, credentials: { credential })
    }
    private func input() throws -> MerchantTemplateAssistInput { try .init(shopName: "Synthetic shop", prompt: "A riddle", method: .secretWord) }
    func testExactTemplateFeatureCannotGrantOtherAIOrPublishing() throws {
        let route = try BusinessRuntimeRoute.post("api/ai/template/fill")
        XCTAssertTrue(BusinessRuntimeFeature.publishingAITemplate.accepts(route))
        for feature: BusinessRuntimeFeature in [.publishingWrite, .publishingRead, .publishingAITheme, .publishingAIClub] { XCTAssertFalse(feature.accepts(route)) }
        XCTAssertFalse(BusinessRuntimeFeature.publishingAITemplate.accepts(try .post("api/ai/node/generate")))
        XCTAssertFalse(BusinessRuntimeFeature.publishingAITemplate.accepts(try .init(method: "GET", path: route.path)))
    }
    func testRuntimeBodyGuardUsesShopNameAndExtraNoteNotIdea() throws {
        let descriptor = try input().assistance.request
        func request(_ fields: [String: ProjectEditJSON]) throws -> URLRequest { try OperationAdapterHTTP.json(configuration: .init(baseURL: base), path: descriptor.path, body: JSONEncoder().encode(fields), token: "synthetic") }
        XCTAssertTrue(PublishingAIRuntimeTransport.validates(try request(descriptor.fields), feature: .publishingAITemplate, baseURL: base))
        var fields = descriptor.fields; fields["shopName"] = .string(" ")
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(fields), feature: .publishingAITemplate, baseURL: base))
        fields = descriptor.fields; fields["extraNote"] = .string("")
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(fields), feature: .publishingAITemplate, baseURL: base))
        fields = descriptor.fields; fields["ownerId"] = .number(901)
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(fields), feature: .publishingAITemplate, baseURL: base))
        fields = descriptor.fields; fields["validationMethod"] = .number(99)
        XCTAssertFalse(PublishingAIRuntimeTransport.validates(try request(fields), feature: .publishingAITemplate, baseURL: base))
    }
    func testDefaultOffWrongRoleAndUSCannotSend() async throws {
        for (approved, role, region) in [(false, "merchant", PublishingRegion.china), (true, "player", .china), (true, "merchant", .unitedStates)] {
            let transport = TemplateAssistTransport(), journal = TemplateAssistJournal()
            let api = try service(transport, journal: journal, approved: approved, role: role, region: region)
            XCTAssertFalse(api.templateConfigured)
            let client = MerchantTemplateAssistClient(service: api)
            do { _ = try await client.generate(input()); XCTFail("Expected disabled") } catch { XCTAssertEqual(error as? MerchantTemplateAssistFailure, .disabled) }
            XCTAssertTrue(transport.requests.isEmpty); XCTAssertTrue(journal.records.isEmpty)
        }
    }
    func testOnlyExplicitClientGenerateDispatchesExactTemplateRequest() async throws {
        let transport = TemplateAssistTransport(), journal = TemplateAssistJournal(), api = try service(transport, journal: journal)
        let client = MerchantTemplateAssistClient(service: api); XCTAssertTrue(transport.requests.isEmpty)
        let result = try await client.generate(input()); XCTAssertEqual(result.text("questionAnswer"), "Lantern")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url, base.appendingPathComponent("api/ai/template/fill")); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody)), try input().assistance.request.fields)
        XCTAssertTrue(journal.records.isEmpty)
    }
    func testHTTPAndEnvelopePermissionRejectionsAreNotProviderFailure() async throws {
        for (status, response) in [(403, "{}"), (401, "{}"), (200, #"{"code":403,"msg":"Forbidden"}"#), (200, #"{"code":500,"msg":"当前身份暂不支持AI创作"}"#)] {
            let transport = TemplateAssistTransport(), journal = TemplateAssistJournal()
            transport.status = status; transport.response = response
            let client = MerchantTemplateAssistClient(service: try service(transport, journal: journal))
            do { _ = try await client.generate(input()); XCTFail("Expected permission rejection") } catch { XCTAssertEqual(error as? MerchantTemplateAssistFailure, .permission) }
            XCTAssertTrue(journal.records.isEmpty)
        }
    }
    func testDefinitiveProviderFailureCanRetryButLostResponseRemainsLocked() async throws {
        let transport = TemplateAssistTransport(), journal = TemplateAssistJournal()
        transport.response = #"{"code":500,"msg":"AI 服务暂时不可用,请稍后重试"}"#
        let client = MerchantTemplateAssistClient(service: try service(transport, journal: journal))
        do { _ = try await client.generate(input()); XCTFail("Expected provider error") } catch { XCTAssertEqual(error as? MerchantTemplateAssistFailure, .provider) }
        XCTAssertTrue(journal.records.isEmpty)
        transport.loseResponse = true
        do { _ = try await client.generate(input()); XCTFail("Expected unknown") } catch { XCTAssertEqual(error as? MerchantTemplateAssistFailure, .unknown) }
        XCTAssertEqual(journal.records.count, 1)
        do { _ = try await client.generate(input()); XCTFail("Expected locked retry") } catch { XCTAssertEqual(error as? MerchantTemplateAssistFailure, .unknown) }
        XCTAssertEqual(transport.requests.count, 2)
    }
    func testAuxiliaryRejectsEmptyShopNameBeforePreparing() throws {
        let transport = TemplateAssistTransport(), api = try service(transport, journal: TemplateAssistJournal())
        let session = try XCTUnwrap(api.templateSession)
        XCTAssertThrowsError(try api.prepare(.template(shopName: " ", extraNote: "A riddle", category: "", reward: "", playStyle: "", validationMethod: nil), session: session))
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
