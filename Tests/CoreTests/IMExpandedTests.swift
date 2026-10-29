import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class IMExpandedFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var body = #"{"code":200}"#
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), status) }
}
@MainActor private final class IMExpandedFakeWriter: IMExpandedWriting {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true
    var mutations: [IMMutation] = []
    var fail = false
    var beforeReturn: (() -> Void)?
    func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
        mutations.append(mutation); beforeReturn?()
        if fail { throw URLError(.timedOut) }
        switch mutation { case .read, .readCursor: return .read; case .mute(_, let muted): return .muted(muted); case .start: return .started(conversationID: 9); case .send: throw URLError(.timedOut) }
    }
    func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw URLError(.timedOut) }
}
final class IMExpandedTests: XCTestCase {
    private var identity: MessagingReadIdentity { .init(accountID: 7, epoch: 1) }
    private func scope() throws -> IMScope { try .init(identity: identity, conversationID: 9) }
    private func service(_ transport: IMExpandedFakeTransport) throws -> IMExpandedService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!), transport: transport, approvedMediaOrigins: ["https://media.example.test"], writesEnabled: true)
    }
    func testConcreteServiceDefaultsOffForEveryMutationAndUpload() async throws {
        let transport = IMExpandedFakeTransport()
        let api = try IMExpandedService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!), transport: transport, approvedMediaOrigins: [])
        let intent = try IMOutgoingIntent(scope: scope(), payload: .route(topicID: 11))
        for mutation in [IMMutation.start(targetMemberID: 42), .read(conversationID: 9), .readCursor(conversationID: 9, lastMessageID: 4, requestID: "ack-cursor-00000001"), .mute(conversationID: 9, muted: true), .send(intent)] {
            do { _ = try await api.perform(mutation, token: "test"); XCTFail("Default must block") } catch { }
        }
        let image = try IMMediaSelection(scope: scope(), bytes: Data([255,216,255]), mimeType: "image/jpeg", fileExtension: "jpg")
        do { _ = try await api.upload(image, consent: .init(scope: scope(), selectionID: image.id, purpose: .upload), token: "test"); XCTFail("Default must block") } catch { }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testRedirectStatusNeverAcknowledgesMutation() async throws {
        let transport = IMExpandedFakeTransport(); transport.status = 302
        do { _ = try await service(transport).perform(.read(conversationID: 9), token: "test"); XCTFail() }
        catch { XCTAssertEqual((error as? MessagingReadFailure)?.httpStatus, 302) }
    }
    func testMalformedStartCannotNavigateToZero() async throws {
        let transport = IMExpandedFakeTransport(); transport.body = #"{"code":200,"data":{"conversationId":0}}"#
        do { _ = try await service(transport).perform(.start(targetMemberID: 42), token: "test"); XCTFail() } catch { }
    }
    @MainActor func testUploadUnknownSurvivesDismissal() async throws {
        let writer = IMExpandedFakeWriter()
        let image = try IMMediaSelection(scope: scope(), bytes: Data([255,216,255]), mimeType: "image/jpeg", fileExtension: "jpg")
        let picker = IMFixtureImagePicker(selection: image)
        let owner = IMImageUploadCoordinator(scope: try scope(), writer: writer, picker: picker,
            journal: ImageJournalTestStorage().journal(), target: try ImageUploadTarget(accountID: image.scope.identity.accountID,
                namespace: "test-deployment", realm: "https://api.example.com", kind: "im", entityID: image.scope.conversationID, field: "image"))
        await owner.selectAfterConsent(); await owner.uploadAfterConsent()
        XCTAssertEqual(owner.visibleState, .outcomeUnknown)
        owner.clear(); XCTAssertEqual(owner.visibleState, .outcomeUnknown)
        await owner.selectAfterConsent(); XCTAssertEqual(picker.selectionCount, 1)
    }
    @MainActor func testUploadJournalSurvivesNewIMOwnerAndEpoch() async throws {
        let storage = ImageJournalTestStorage(), writer = IMExpandedFakeWriter(), initial = try scope()
        let target = try ImageUploadTarget(accountID: initial.identity.accountID, namespace: "test-deployment",
            realm: "https://api.example.com", kind: "im", entityID: initial.conversationID, field: "image")
        let image = try IMMediaSelection(scope: initial, bytes: Data([255,216,255]), mimeType: "image/jpeg", fileExtension: "jpg")
        let first = IMImageUploadCoordinator(scope: initial, writer: writer, picker: IMFixtureImagePicker(selection: image), journal: storage.journal(), target: target)
        await first.selectAfterConsent(); await first.uploadAfterConsent()
        writer.identity = .init(accountID: initial.identity.accountID, epoch: initial.identity.epoch + 1)
        let next = try IMScope(identity: XCTUnwrap(writer.identity), conversationID: initial.conversationID)
        let picker = IMFixtureImagePicker(selection: nil)
        let recreated = IMImageUploadCoordinator(scope: next, writer: writer, picker: picker, journal: storage.journal(), target: target)
        await recreated.selectAfterConsent()
        XCTAssertEqual(recreated.visibleState, .outcomeUnknown); XCTAssertEqual(picker.selectionCount, 0)
    }
    func testSourceStartReadMuteRequests() async throws {
        let transport = IMExpandedFakeTransport(); let api = try service(transport)
        transport.body = #"{"code":200,"data":{"conversationId":9}}"#
        let started = try await api.perform(.start(targetMemberID: 42), token: "test")
        XCTAssertEqual(started, .started(conversationID: 9))
        XCTAssertTrue(String(data: transport.requests[0].httpBody!, encoding: .utf8)!.contains("target_member_id"))
        transport.body = #"{"code":200}"#
        let muted = try await api.perform(.mute(conversationID: 9, muted: false), token: "test")
        XCTAssertEqual(muted, .muted(false))
        XCTAssertTrue(String(data: transport.requests[1].httpBody!, encoding: .utf8)!.contains("\r\n0\r\n"))
        let read = try await api.perform(.read(conversationID: 9), token: "test")
        XCTAssertEqual(read, .read)
        let plain = String(data: transport.requests[2].httpBody!, encoding: .utf8)!
        XCTAssertFalse(plain.contains("request_id"))
        XCTAssertFalse(plain.contains("last_message_id"))
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["start", "mute", "read"])
    }
    func testChannelReadSendsCursorAndKeepsTheSameRequest() async throws {
        let transport = IMExpandedFakeTransport(); let api = try service(transport)
        let requestID = "ack-cursor-00000001"
        let applied: [String: Any] = ["code": 200, "data": [
            "request_id": requestID, "operation": "ACK", "scope_type": 1, "scope_id": "9",
            "status": "APPLIED", "replayed": false, "must_refresh_state": false, "result_redacted": false
        ]]
        transport.body = String(data: try JSONSerialization.data(withJSONObject: applied), encoding: .utf8)!
        let receipt = try await api.perform(.readCursor(conversationID: 9, lastMessageID: 44, requestID: requestID), token: "test")
        XCTAssertEqual(receipt, .read)
        let sent = String(data: transport.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(sent.contains("conversation_id"))
        XCTAssertTrue(sent.contains("last_message_id"))
        XCTAssertTrue(sent.contains(requestID))
        XCTAssertEqual(transport.requests.count, 1)
        let pending: [String: Any] = ["code": 200, "data": [
            "request_id": requestID, "operation": "ACK", "scope_type": 1, "scope_id": "9",
            "status": "PENDING", "outcome": "UNKNOWN", "replayed": false, "must_refresh_state": false,
            "resume_with_same_request": true, "result_redacted": false
        ]]
        transport.body = String(data: try JSONSerialization.data(withJSONObject: pending), encoding: .utf8)!
        do {
            _ = try await api.perform(.readCursor(conversationID: 9, lastMessageID: 44, requestID: requestID), token: "test")
            XCTFail()
        } catch { XCTAssertEqual(error as? IMCapabilityGap, .unknownOutcome) }
        XCTAssertEqual(transport.requests.count, 2)
        transport.requests.removeAll()
        do {
            _ = try await api.perform(.readCursor(conversationID: 9, lastMessageID: 44, requestID: " short "), token: "test")
            XCTFail()
        } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testProjectedRouteReceiptKeepsTopicAndClientMessage() async throws {
        let key = String(repeating: "c", count: 32)
        let intent = try IMOutgoingIntent(scope: scope(), payload: .route(topicID: 11), clientMessageID: key)
        let transport = IMExpandedFakeTransport()
        let api = try service(transport)
        func body(_ content: String, topic: Int) throws -> String {
            let message: [String: Any] = [
                "id": 3, "conversationId": 9, "senderId": 7, "status": 0, "msgType": 3,
                "content": content, "extraJson": #"{"cardType":"route","topicId":\#(topic)}"#,
                "clientMessageId": key
            ]
            return String(data: try JSONSerialization.data(withJSONObject: ["code": 200, "data": message]), encoding: .utf8)!
        }
        transport.body = try body("[路线] 西湖", topic: 11)
        guard case .sent(let message) = try await api.perform(.send(intent), token: "test") else { return XCTFail() }
        XCTAssertEqual(message.content, "[路线] 西湖")
        transport.body = try body("路线已不可用", topic: 11)
        guard case .sent = try await api.perform(.send(intent), token: "test") else { return XCTFail() }
        transport.body = try body("[路线] 西湖", topic: 12)
        do { _ = try await api.perform(.send(intent), token: "test"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testRouteAndLocationWireFieldsAreSourceExact() throws {
        let route = try IMOutgoingPayload.route(topicID: 11).wireFields(approvedOrigins: [])
        XCTAssertEqual(route["msg_type"], "3"); XCTAssertEqual(route["content"], "[路线]")
        let json = try JSONSerialization.jsonObject(with: Data(route["extra_json"]!.utf8)) as! [String: Any]
        XCTAssertEqual(json["topicId"] as? Int, 11); XCTAssertEqual(json["cardType"] as? String, "route")
        XCTAssertThrowsError(try IMOutgoingPayload.location(name: "", address: "", latitude: .nan, longitude: 10).wireFields(approvedOrigins: []))
        XCTAssertThrowsError(try IMOutgoingPayload.image(URL(string: "https://evil.example/x")!).wireFields(approvedOrigins: ["https://media.example.test"]))
    }
    func testImageSelectionSizeMIMEAndConsent() async throws {
        let transport = IMExpandedFakeTransport(); let api = try service(transport)
        let selection = try IMMediaSelection(scope: scope(), bytes: Data([255,216,255,0]), mimeType: "image/jpeg", fileExtension: "jpg")
        do { _ = try await api.upload(selection, consent: .init(scope: scope(), selectionID: UUID(), purpose: .upload), token: "test"); XCTFail() } catch { XCTAssertEqual(error as? IMCapabilityGap, .consentRequired) }
        XCTAssertTrue(transport.requests.isEmpty)
        transport.body = #"{"code":200,"url":"https://media.example.test/image.jpg"}"#
        let uploaded = try await api.upload(selection, consent: .init(scope: scope(), selectionID: selection.id, purpose: .upload), token: "test")
        XCTAssertEqual(uploaded.host, "media.example.test")
        XCTAssertEqual(transport.requests[0].url?.lastPathComponent, "uploadOSS")
        XCTAssertTrue(String(decoding: transport.requests[0].httpBody!, as: UTF8.self).contains("name=\"file\""))
        XCTAssertThrowsError(try IMMediaSelection(scope: scope(), bytes: Data([1]), mimeType: "image/jpeg", fileExtension: "../x"))
    }
    func testRefreshEpochAndGenerationRejectStaleCompletion() throws {
        var gate = IMRefreshGate(); let first = gate.begin(try scope()); let second = gate.begin(try scope())
        XCTAssertFalse(gate.finish(first, scope: try scope())); XCTAssertTrue(gate.finish(second, scope: try scope()))
        XCTAssertFalse(gate.finish(second, scope: try scope()))
        let third = gate.begin(try scope()); gate.cancel(); XCTAssertFalse(gate.finish(third, scope: try scope()))
    }
    @MainActor func testUnknownMutationCannotBeReplacedAndRetryRetainsIntent() async throws {
        let writer = IMExpandedFakeWriter(); writer.fail = true
        let owner = IMExpandedCoordinator(scope: try scope(), writer: writer)
        let intent = try IMOutgoingIntent(scope: scope(), payload: .route(topicID: 11))
        XCTAssertTrue(owner.review(.send(intent))); await owner.confirm()
        XCTAssertEqual(owner.visibleState, .outcomeUnknown(.send(intent)))
        XCTAssertFalse(owner.review(.read(conversationID: 9)))
        await owner.retryUnchanged(); XCTAssertEqual(writer.mutations, [.send(intent), .send(intent)])
        writer.identity = .init(accountID: 7, epoch: 2)
        XCTAssertEqual(owner.visibleState, .idle); await owner.retryUnchanged(); XCTAssertEqual(writer.mutations.count, 2)
    }
    @MainActor func testScopeMismatchAndSessionChangeDoNotPublishReceipt() async throws {
        let writer = IMExpandedFakeWriter(); let owner = IMExpandedCoordinator(scope: try scope(), writer: writer)
        XCTAssertFalse(owner.review(.read(conversationID: 8)))
        writer.beforeReturn = { writer.identity = .init(accountID: 8, epoch: 2) }
        XCTAssertTrue(owner.review(.read(conversationID: 9))); await owner.confirm(); XCTAssertEqual(owner.visibleState, .idle)
    }
    @MainActor func testDormantWriterDoesNotStartOrUpload() async throws {
        let writer = IMExpandedWriter(session: { nil }); XCTAssertFalse(writer.isConfigured)
        do { _ = try await writer.perform(.start(targetMemberID: 2), expectedIdentity: identity); XCTFail() } catch { }
    }
    func testUntrustedResultNeverBecomesReviewAction() throws {
        let raw = #"{"id":1,"conversationId":9,"senderId":7,"status":0,"msgType":3,"content":"hi","extraJson":"{\"result\":{\"outcome\":\"approved\"},\"buttons\":[{\"text\":\"Open\",\"action\":\"https://evil.example\"}]}"}"#
        let message = try JSONDecoder().decode(MessagingMessage.self, from: Data(raw.utf8))
        XCTAssertEqual(IMCardAction.actions(for: message).first?.destination, .unsupported)
    }
}
