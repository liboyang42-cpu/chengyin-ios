import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

actor EngagementRecordingTransport: MerchantBusinessTestTransport {
    var requests: [URLRequest] = []
    var accessJSON = MerchantEngagementSyntheticFixtures.access
    var responses: [String:String]
    var unknownPaths: Set<String> = []
    var binary = MerchantEngagementSyntheticFixtures.workbookBytes
    init(_ responses: [String:String] = [:]) { self.responses = responses }
    func setAccess(_ raw: String) { accessJSON = raw }
    func setUnknown(_ path: String) { unknownPaths.insert(path) }
    func setResponse(_ path: String, _ raw: String) { responses[path] = raw }
    func setBinary(_ bytes: Data) { binary = bytes }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let path = request.url?.path ?? ""
        if unknownPaths.contains(path) { throw URLError(.timedOut) }
        if path.hasSuffix("/download") { return (binary, 200) }
        let raw: String
        if path.hasSuffix("access/me") { raw = accessJSON }
        else if let supplied = responses[path] { raw = supplied }
        else {
            switch path {
            case "/api/merchant/crm/segments": raw = request.httpMethod == "GET" ? MerchantEngagementSyntheticFixtures.segments : #"{"id":71002}"#
            case "/api/merchant/crm/campaigns/coupons": raw = MerchantEngagementSyntheticFixtures.coupons
            case "/api/merchant/crm/campaigns/preview": raw = MerchantEngagementSyntheticFixtures.audience
            case "/api/merchant/crm/broadcast/preview": raw = MerchantEngagementSyntheticFixtures.broadcast
            case "/api/merchant/crm/campaigns/73001", "/api/merchant/crm/campaigns/73001/dispatch": raw = MerchantEngagementSyntheticFixtures.campaign
            case "/api/merchant/crm/campaigns": raw = request.httpMethod == "GET" ? "[\(MerchantEngagementSyntheticFixtures.campaign)]" : MerchantEngagementSyntheticFixtures.campaign
            case "/api/merchant/crm/customers/61001/detail": raw = MerchantBusinessSyntheticFixtures.customer
            case "/api/merchant/crm/customers/61001/contact": raw = #"{"phone":"+1 (202) 555-0100"}"#
            case "/api/merchant/crm/exports": raw = #"{"id":74001,"status":"PENDING","downloadToken":"synthetic-download-token"}"#
            case "/api/merchant/crm/exports/74001/status": raw = MerchantEngagementSyntheticFixtures.exportTask
            default: raw = "{}"
            }
        }
        return (Data("{\"code\":200,\"data\":\(raw)}".utf8), 200)
    }
}
final class MerchantEngagementServiceTests: XCTestCase {
    private func service(_ transport: EngagementRecordingTransport, enabled: Bool = false) throws -> MerchantEngagementService {
        try .init(configuration: .init(baseURL: URL(string: "https://example.com")!), readTransport: transport, testingActionTransport: enabled ? transport : nil)
    }
    private func access() throws -> MerchantEngagementAccess { try .init(MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.access).object!) }
    func testSegmentReadUsesGETWithoutJSONBody() async throws {
        let fake = EngagementRecordingTransport(); let result = try await service(fake).read(.segments, access: access(), token: "synthetic-token")
        guard case .segments(let values) = result else { return XCTFail() }; XCTAssertEqual(values.first?.id, 71001)
        let request = await fake.requests.first; XCTAssertEqual(request?.httpMethod,"GET"); XCTAssertNil(request?.httpBody)
    }
    func testCampaignPreviewPOSTContainsOnlySegmentAndChannel() async throws {
        let fake = EngagementRecordingTransport()
        _ = try await service(fake).read(.campaignPreview(71001,.inApp), access: access(), token: "synthetic-token")
        let requests = await fake.requests; let body = try XCTUnwrap(requests.first?.httpBody)
        let fields = try JSONDecoder().decode(MerchantBusinessValue.self,from: body).object!
        XCTAssertEqual(Set(fields.keys),Set(["segmentId","channel"]))
    }
    func testDefaultActionGateDoesNotSendAnyRequest() async throws {
        let fake = EngagementRecordingTransport()
        do { _ = try await service(fake).execute(.createExport(.init()), requestID:"example-request",access:access(),token:"synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure,.disabled) }
        let count = await fake.requests.count; XCTAssertEqual(count,0)
    }
    func testDormantSegmentSaveActuallySendsAndDecodes() async throws {
        let fake = EngagementRecordingTransport()
        let receipt = try await service(fake,enabled:true).execute(.saveSegment(name:"Example",filter:.init()),requestID:"example-request",access:access(),token:"synthetic-token")
        guard case .savedSegment = receipt else { return XCTFail() }
        let requests = await fake.requests; XCTAssertEqual(requests.first?.httpMethod,"POST"); XCTAssertEqual(requests.first?.url?.path,"/api/merchant/crm/segments")
    }
    func testExportCreationReturnsMemoryOnlyToken() async throws {
        let fake = EngagementRecordingTransport()
        let result = try await service(fake,enabled:true).execute(.createExport(.init()),requestID:"example-request",access:access(),token:"synthetic-token")
        guard case .exportCreated(let ticket) = result else { return XCTFail() }; XCTAssertEqual(ticket.downloadToken,"synthetic-download-token"); XCTAssertFalse(ticket.canDownload)
    }
    func testExportDownloadUsesExactPathAndDedicatedHeader() async throws {
        let fake = EngagementRecordingTransport()
        let ticket = try MerchantExportTicket(creation:["id":.int(74001),"status":.string("SUCCESS"),"rowCount":.int(7),"downloadToken":.string("synthetic-download-token")])
        _ = try await service(fake,enabled:true).downloadSynthetic(ticket,token:"synthetic-token")
        let request = await fake.requests.first
        XCTAssertEqual(request?.httpMethod,"GET"); XCTAssertEqual(request?.url?.path,"/api/merchant/crm/exports/74001/download")
        XCTAssertEqual(request?.value(forHTTPHeaderField:"X-CRM-Export-Token"),"synthetic-download-token"); XCTAssertNil(request?.url?.query)
    }
    func testExportRejectsJSONMasqueradingAsWorkbook() async throws {
        let fake = EngagementRecordingTransport(); await fake.setBinary(Data(#"{"code":403}"#.utf8))
        let ticket = try MerchantExportTicket(creation:["id":.int(74001),"status":.string("SUCCESS"),"rowCount":.int(7),"downloadToken":.string("synthetic-download-token")])
        do { _ = try await service(fake,enabled:true).downloadSynthetic(ticket,token:"synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure,.malformed) }
    }
    func testCouponPreviewRequiresCouponPermissionEvenWithMarketing() async throws {
        let fake = EngagementRecordingTransport()
        var raw = try MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.access).object!
        raw["permissions"] = .array(raw["permissions"]!.array!.filter { $0 != .string("merchant:coupon:manage") })
        do { _ = try await service(fake).read(.campaignPreview(1,.coupon),access:.init(raw),token:"synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure,.denied) }
        let count = await fake.requests.count; XCTAssertEqual(count,0)
    }
    func testAcceptInvitationDecodesOperatorIDWithoutInferringMerchant() async throws {
        let path = "/api/merchant/operators/invite/accept"
        let fake = EngagementRecordingTransport([path:#"{"id":75001,"roleCode":"MERCHANT_CHECKIN","status":"ACTIVE","acceptedAt":"2026-10-02","version":0}"#])
        let result = try await service(fake,enabled:true).execute(.acceptInvitation(.init(token:"synthetic-invitation-token")),requestID:"example-request",access:.init(["active":.bool(false)]),token:"synthetic-token")
        guard case .invitationAccepted(let member) = result else { return XCTFail() }; XCTAssertEqual(member.id,"75001"); XCTAssertNil(member.fields["merchantId"])
    }
    func testAcceptanceRejectsRevokedReceipt() async throws {
        let fake = EngagementRecordingTransport(["/api/merchant/operators/invite/accept":#"{"id":75001,"roleCode":"MERCHANT_CHECKIN","status":"REVOKED","acceptedAt":"2026-10-02","version":0}"#])
        do { _ = try await service(fake,enabled:true).execute(.acceptInvitation(.init(token:"synthetic-invitation-token")),requestID:"example-request",access:.init(["active":.bool(false)]),token:"synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure,.malformed) }
    }
    func testContactRevealIsExplicitActionNotReadQuery() async throws {
        let fake = EngagementRecordingTransport()
        let result = try await service(fake,enabled:true).execute(.contact(.init(61001),.copy),requestID:"example-request",access:access(),token:"synthetic-token")
        guard case .contact(let contact) = result else { return XCTFail() }; XCTAssertEqual(contact.purpose,.copy)
        let count = await fake.requests.count; XCTAssertEqual(count,1)
    }
}
