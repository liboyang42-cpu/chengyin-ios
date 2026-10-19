import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class StoreDayFakeTransport: PlayStoreDayOfflineTransport, @unchecked Sendable {
    enum Reply { case json(String, Int), failure }
    var replies: [String: [Reply]] = [:]
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        guard var queue = replies[path], !queue.isEmpty else { return (Data(#"{"code":404}"#.utf8), 404) }
        let reply = queue.count > 1 ? queue.removeFirst() : queue[0]
        replies[path] = queue
        switch reply {
        case .json(let body, let status): return (Data(body.utf8), status)
        case .failure: throw URLError(.timedOut)
        }
    }
    func paths() -> [String] { requests.compactMap { $0.url?.path } }
}
private func wire(_ json: String) -> PlayWireValue { (try? JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8))) ?? .null }
private let listRow = #"{"nodeId":701,"merchantId":81,"name":"Synthetic store","imgUrl":"https://fixture.example/a.jpg,https://fixture.example/b.jpg","ruleInstructions":"List rule","photoRequireDesc":"List photo","crowded":true,"inStoreLoad":3,"serviceCapacity":{"perHour":12},"expectedWaitMinutes":15,"quantityUnavailable":false,"arrived":false,"selfReported":false,"done":false,"hasGame":true,"validationMethod":3}"#

final class PlayStoreDayPresentationTests: XCTestCase {
    func testRowDecodesSourceFieldsAndReceiptNamesWin() throws {
        let node = try XCTUnwrap(PlayStoreDayNode(row: wire(listRow)))
        XCTAssertEqual(node.heroImage, "https://fixture.example/a.jpg")
        XCTAssertEqual(node.merchantID, 81); XCTAssertEqual(node.servicePerHour, 12); XCTAssertEqual(node.expectedWaitMinutes, 15)
        XCTAssertEqual(node.rule, "List rule"); XCTAssertEqual(node.photoDescription, "List photo")
        XCTAssertNil(node.latitude); XCTAssertFalse(node.hasCoordinates)
        let merged = node.merging(wire(#"{"nodeId":999,"arrived":true,"rule":"Receipt rule","photoDesc":"Receipt photo","question":"Q","options":{"B":"two","A":"one"}}"#))
        XCTAssertEqual(merged.id, 701); XCTAssertTrue(merged.arrived)
        XCTAssertEqual(merged.rule, "Receipt rule"); XCTAssertEqual(merged.photoDescription, "Receipt photo")
        XCTAssertEqual(merged.options?.map(\.key), ["A", "B"])
        XCTAssertTrue(node.proofLanded(after: merged)); XCTAssertFalse(merged.proofLanded(after: merged))
    }
    func testAdvancedConfigAndMissingIdentity() {
        XCTAssertNil(PlayStoreDayNode(row: wire(#"{"name":"no id"}"#)))
        let advanced = PlayStoreDayNode(row: wire(#"{"nodeId":7,"advancedConfigJson":"{\"schemaVersion\":1,\"random\":{\"enabled\":true}}"}"#))
        XCTAssertEqual(advanced?.hasAdvanced, true)
        let schemaOnly = PlayStoreDayNode(row: wire(#"{"nodeId":7,"advancedConfigJson":"{\"schemaVersion\":1}"}"#))
        XCTAssertEqual(schemaOnly?.hasAdvanced, false)
    }
    func testTagCrowdPrimaryAndPopupPriority() throws {
        var node = try XCTUnwrap(PlayStoreDayNode(row: wire(listRow)))
        XCTAssertEqual(PlayStoreDayHeaderTag(node), .pending); XCTAssertEqual(PlayStoreDayCrowd(node), .queue)
        XCTAssertEqual(PlayStoreDayPrimaryAction.resolve(node, receipt: .ready), .scan)
        XCTAssertEqual(PlayStoreDayPrimaryAction.resolve(node, receipt: .unknown), .confirmPending)
        XCTAssertEqual(PlayStoreDayPopup.resolve(node), PlayStoreDayPopup.none)
        node = node.merging(wire(#"{"arrived":true}"#))
        XCTAssertEqual(PlayStoreDayHeaderTag(node), .arrived)
        XCTAssertEqual(PlayStoreDayPopup.resolve(node), .taskCard, "hasGame without question falls back to the task card")
        XCTAssertEqual(PlayStoreDayPopup.resolve(node.merging(wire(#"{"question":"Q"}"#))), .quiz)
        XCTAssertEqual(PlayStoreDayPopup.resolve(node.merging(wire(#"{"validationMethod":6,"question":"Q"}"#))), .preferenceHandoff)
        XCTAssertEqual(PlayStoreDayPopup.resolve(node.merging(wire(#"{"hasAdvanced":true,"validationMethod":6}"#))), .advancedHandoff)
        node = node.merging(wire(#"{"selfReported":true}"#))
        XCTAssertEqual(PlayStoreDayPrimaryAction.resolve(node, receipt: .confirmed), .verify)
        node = node.merging(wire(#"{"done":true,"crowded":null}"#))
        XCTAssertEqual(PlayStoreDayHeaderTag(node), .redeemed); XCTAssertEqual(PlayStoreDayCrowd(node), .unknown)
        XCTAssertEqual(PlayStoreDayPrimaryAction.resolve(node, receipt: .ready), .redeemed)
        XCTAssertEqual(PlayStoreDayPopup.resolve(node), PlayStoreDayPopup.none)
    }
    func testOpenTextServerWinsThenWindowThenHidden() {
        XCTAssertEqual(PlayStoreDayOpenText.resolve(openStatus: "即将打烊", businessTime: "09:00-21:00", nowMinutes: 0), .server("即将打烊"))
        XCTAssertEqual(PlayStoreDayOpenText.resolve(openStatus: nil, businessTime: "09:00-21:00", nowMinutes: 600), .open)
        XCTAssertEqual(PlayStoreDayOpenText.resolve(openStatus: "", businessTime: "09:00 至 21:00", nowMinutes: 1300), .closed)
        XCTAssertEqual(PlayStoreDayOpenText.resolve(openStatus: nil, businessTime: "22:00~02:00", nowMinutes: 30), .open)
        XCTAssertNil(PlayStoreDayOpenText.resolve(openStatus: nil, businessTime: "all day", nowMinutes: 30))
    }
    func testConsentRequestIDAndState() {
        XCTAssertEqual(PlayStoreDayConsent.requestID(event: .agree, merchantID: 81, milliseconds: 1_700_000_000_000), "merchant-agree-81-1700000000000")
        XCTAssertEqual(PlayStoreDayConsent.requestID(event: .revoke, merchantID: 81, milliseconds: 5), "merchant-revoke-81-5")
        XCTAssertNil(PlayStoreDayConsent.requestID(event: .agree, merchantID: 0, milliseconds: 5))
        XCTAssertEqual(PlayStoreDayConsent.state(latest: nil, merchantID: 81), PlayStoreDayConsentState.none)
        let agree = try? JSONDecoder().decode(ComplianceConsent.self, from: Data(#"{"docType":"merchant_onsite_data_sharing","scene":"merchant_redeem","scopeType":"MERCHANT","scopeId":81,"eventType":"AGREE"}"#.utf8))
        XCTAssertEqual(PlayStoreDayConsent.state(latest: agree, merchantID: 81), .agree)
        XCTAssertEqual(PlayStoreDayConsent.state(latest: agree, merchantID: 82), .unavailable)
    }
    func testAnswerRewardOnlyOnFirstCompletion() {
        XCTAssertEqual(PlayStoreDayAnswerResult(message: "答对了！", data: wire(#"{"firstTime":true,"xp":9}"#)).experience, 9)
        XCTAssertNil(PlayStoreDayAnswerResult(message: nil, data: wire(#"{"firstTime":false,"xp":0}"#)).experience)
        XCTAssertTrue(PlayStoreDayAnswerResult.readbackRecorded.confirmedByReadback)
    }
}

@MainActor final class PlayStoreDayServiceTests: XCTestCase {
    private let session = try? PlayStoreDaySession(accountID: 9001, epoch: 1, token: "synthetic-token")
    private func service(_ transport: StoreDayFakeTransport, execution: PlayStoreDayService.Execution = .injectedOfflineHarness) -> PlayStoreDayService {
        let current = session
        return PlayStoreDayService(configuration: try? APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport,
                                   market: .china, execution: execution, readsEnabled: true, currentSession: { current })
    }
    func testProductionDefaultsSendNoWrites() async {
        let transport = StoreDayFakeTransport()
        let disabled = service(transport, execution: .disabled)
        XCTAssertFalse(disabled.permitsProofWrites); XCTAssertFalse(disabled.permitsConsentWrites)
        XCTAssertFalse(MerchantCityNPCParityGates.disabled.storeDayProofWrites); XCTAssertFalse(MerchantCityNPCParityGates.disabled.storeDayConsentWrites)
        let checkin = await disabled.checkin(scope: .topic(71), code: "SYNTHETIC")
        let consent = await disabled.consent(merchantID: 81, event: .agree, requestID: "merchant-agree-81-1")
        XCTAssertEqual(checkin, .rejected(nil)); XCTAssertEqual(consent, .rejected(nil))
        XCTAssertTrue(transport.requests.isEmpty)
        var gates = MerchantCityNPCParityGates(); gates.storeDayProofWrites = true
        let gated = PlayStoreDayService(configuration: try? APIConfiguration(baseURL: URL(string: "https://example.com/")!), transport: transport, market: .china, gates: gates, currentSession: { nil })
        XCTAssertFalse(gated.permitsProofWrites, "a flag without a reviewed endpoint never dispatches")
    }
    func testRequestsMatchMiniProgram() async throws {
        let transport = StoreDayFakeTransport()
        transport.replies["/fixture/api/play/nodes"] = [.json(#"{"code":200,"data":{"nodes":[\#(listRow)]}}"#, 200)]
        transport.replies["/fixture/api/play/checkin"] = [.json(#"{"code":200,"msg":"已记录到店","data":{"nodeId":701,"arrived":true}}"#, 200)]
        transport.replies["/fixture/api/compliance/consents"] = [.json(#"{"code":200,"data":{}}"#, 200)]
        let api = service(transport)
        let node = try await api.node(scope: .topic(71), nodeID: 701)
        XCTAssertEqual(node?.id, 701)
        XCTAssertEqual(transport.requests[0].httpMethod, "GET"); XCTAssertEqual(transport.requests[0].url?.query, "topicId=71")
        guard case .confirmed(let message, _) = await api.checkin(scope: .topic(71), code: " SYNTHETIC ") else { return XCTFail() }
        XCTAssertEqual(message, "已记录到店")
        let body = String(data: transport.requests[1].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"code\"\r\n\r\nSYNTHETIC\r\n")); XCTAssertTrue(body.contains("name=\"topicId\"\r\n\r\n71\r\n"))
        XCTAssertFalse(body.contains("name=\"nodeId\"")); XCTAssertFalse(body.contains("registrationId"))
        _ = await api.consent(merchantID: 81, event: .agree, requestID: "merchant-agree-81-1")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[2].httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(Set(json.keys), ["docType", "scene", "scopeType", "scopeId", "eventType", "requestId"])
        XCTAssertEqual(json["docType"] as? String, "merchant_onsite_data_sharing"); XCTAssertEqual(json["scene"] as? String, "merchant_redeem")
    }
    func testOutcomeClassification() async {
        let transport = StoreDayFakeTransport()
        let api = service(transport)
        transport.replies["/fixture/api/play/photo"] = [.json("", 503)]
        let gateway = await api.photo(scope: .topic(71), nodeID: 701, pictureURL: "https://fixture.example/p.jpg")
        XCTAssertEqual(gateway, .unknown)
        transport.replies["/fixture/api/play/photo"] = [.failure]
        let network = await api.photo(scope: .topic(71), nodeID: 701, pictureURL: "https://fixture.example/p.jpg")
        XCTAssertEqual(network, .unknown)
        transport.replies["/fixture/api/play/answer"] = [.json(#"{"code":500,"msg":"答案不正确","data":{"answerWrong":true}}"#, 200)]
        let wrong = await api.answer(scope: .topic(71), nodeID: 701, answer: "A")
        XCTAssertEqual(wrong, .rejected("答案不正确"))
        let insecure = await api.photo(scope: .topic(71), nodeID: 701, pictureURL: "http://fixture.example/p.jpg")
        XCTAssertEqual(insecure, .rejected(nil))
    }
    func testUnknownCheckinIsResolvedByReadbackNotResent() async {
        let transport = StoreDayFakeTransport()
        let arrivedRow = listRow.replacingOccurrences(of: #""arrived":false"#, with: #""arrived":true"#)
        transport.replies["/fixture/api/play/nodes"] = [.json(#"{"code":200,"data":{"nodes":[\#(listRow)]}}"#, 200), .json(#"{"code":200,"data":{"nodes":[\#(arrivedRow)]}}"#, 200)]
        transport.replies["/fixture/api/play/checkin"] = [.failure]
        transport.replies["/fixture/api/compliance/consents/latest"] = [.json(#"{"code":200,"data":{}}"#, 200)]
        final class Evidence: PlayStoreDayEvidenceSource { func storeCode() -> String? { "SYNTHETIC" }; func proofPictureURL() -> String? { nil } }
        let model = PlayStoreDayCoordinator(nodeID: 701, scope: .topic(71), registrationID: 41, justScanned: false, service: service(transport), evidence: Evidence())
        await model.load()
        XCTAssertEqual(model.phase, .loaded); XCTAssertEqual(model.consent, PlayStoreDayConsentState.none)
        model.prepareScan()
        guard let prepared = model.preparedProof else { return XCTFail() }
        await model.submitProof(prepared)
        XCTAssertEqual(model.notice, .proofLanded); XCTAssertEqual(model.receipt, .confirmed); XCTAssertEqual(model.node?.arrived, true)
        XCTAssertEqual(transport.paths().filter { $0.hasSuffix("/checkin") }.count, 1)
        XCTAssertTrue(model.taskVisible, "landed arrival keeps the carried auto-popup")
    }
    func testVerificationGuardsAndConsentReadbackMismatch() async {
        let transport = StoreDayFakeTransport()
        let redeemedRow = listRow.replacingOccurrences(of: #""arrived":false,"selfReported":false"#, with: #""arrived":true,"selfReported":true"#)
        transport.replies["/fixture/api/play/nodes"] = [.json(#"{"code":200,"data":{"nodes":[\#(redeemedRow)]}}"#, 200)]
        transport.replies["/fixture/api/compliance/consents/latest"] = [.json(#"{"code":200,"data":{}}"#, 200)]
        transport.replies["/fixture/api/compliance/consents"] = [.json(#"{"code":200,"data":{}}"#, 200)]
        let noTicket = PlayStoreDayCoordinator(nodeID: 701, scope: .topic(71), registrationID: 0, justScanned: false, service: service(transport))
        await noTicket.load(); noTicket.openVerifyCode()
        XCTAssertEqual(noTicket.notice, .needTicket)
        var presented = false
        let model = PlayStoreDayCoordinator(nodeID: 701, scope: .topic(71), registrationID: 41, justScanned: false, service: service(transport),
                                            presentVerification: { presented = true; return true })
        await model.load(); model.openVerifyCode()
        XCTAssertTrue(model.consentPromptVisible)
        await model.agreeConsent()
        XCTAssertFalse(presented); XCTAssertEqual(model.consent, .unavailable); XCTAssertEqual(model.notice, .consentUnconfirmed)
    }
}
