import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelHostNeighborMigrationTests: XCTestCase {
    private let key = "11111111-1111-4111-8111-111111111111"
    private func context(epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://api.example.test")!, role: "player",
              session: try .init(accountID: 7, epoch: epoch, namespace: "CN:host-test", token: "fixture-token"))
    }
    private func scope() throws -> IMScope { try .init(identity: .init(accountID: 7, epoch: 1), conversationID: 9) }
    private func payloads() throws -> [IMOutgoingPayload] {
        [.voice(.init(uploadRequestID: key, assetID: 5, durationMS: 1000, waveform: "AQ==", size: 100)),
         .file(.init(uploadRequestID: key, attachmentID: "5", name: "a.txt", size: 100, mime: "text/plain", ext: "txt", sha256: String(repeating: "a", count: 64))),
         .video(.init(uploadRequestID: key, attachmentID: "5", sha256: String(repeating: "a", count: 64), coverSHA256: String(repeating: "b", count: 64), size: 100, coverSize: 100, durationMS: 1000, width: 8, height: 8)),
         .staticLocation(try .init(name: "Park", address: "", latitude: 31, longitude: 121, datum: "WGS84"))]
    }
    private func service(_ wire: NeighborWire, voice: Bool = false, file: Bool = false, video: Bool = false, location: Bool = false) throws -> IMExpandedService {
        try .init(configuration: .init(baseURL: context().baseURL), transport: wire, approvedMediaOrigins: [], writesEnabled: true,
            enabledPaths: ["api/im/send", "api/im/send-receipt"], staticLocationReceiptEnabled: location,
            voiceReceiptEnabled: voice, fileReceiptEnabled: file, videoReceiptEnabled: video)
    }
    func testGenericIMSendCannotSendAnyNewMediaPayload() async throws {
        let wire = NeighborWire(); let api = try service(wire)
        for payload in try payloads() {
            do { _ = try await api.perform(.send(.init(scope: scope(), payload: payload)), token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGenericReadSentCannotRecoverNewMediaPayloads() async throws {
        let wire = NeighborWire(); let api = try service(wire, voice: true, file: true, video: true, location: true)
        for payload in try payloads() {
            do { _ = try await api.readSent(.init(scope: scope(), payload: payload), token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testVoiceReceiptOnlyReadsOriginalKeyWithoutSendPermission() async throws { try await receiptOnly(index: 0) }
    func testFileReceiptOnlyReadsOriginalKeyWithoutSendPermission() async throws { try await receiptOnly(index: 1) }
    func testVideoReceiptOnlyReadsOriginalKeyWithoutSendPermission() async throws { try await receiptOnly(index: 2) }
    func testStaticLocationReceiptOnlyReadsOriginalKeyWithoutSendPermission() async throws { try await receiptOnly(index: 3) }
    private func receiptOnly(index: Int) async throws {
        let wire = NeighborWire(); let api = try service(wire, voice: index == 0, file: index == 1, video: index == 2, location: index == 3)
        let intent = try IMOutgoingIntent(scope: scope(), payload: payloads()[index], clientMessageID: String(repeating: "c", count: 32))
        let found: MessagingMessage?
        switch index {
        case 0: found = try await api.recoverVoice(intent, token: "fixture-token")
        case 1: found = try await api.recoverFile(intent, token: "fixture-token")
        case 2: found = try await api.recoverVideo(intent, token: "fixture-token")
        default: found = try await api.recoverStaticLocation(intent, token: "fixture-token")
        }
        XCTAssertNil(found); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(wire.requests[0].url?.path, "/api/im/send-receipt")
        XCTAssertTrue(String(decoding: try XCTUnwrap(wire.requests[0].httpBody), as: UTF8.self).contains(intent.clientMessageID))
        do { _ = try await api.perform(.send(intent), token: "fixture-token"); XCTFail() } catch { }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testTypedMediaReceiptsRejectWrongOriginalMessageIdentity() async throws {
        let wire = NeighborWire(); let api = try service(wire, voice: true, file: true, video: true)
        for (index, payload) in try payloads().prefix(3).enumerated() {
            let intent = try IMOutgoingIntent(scope: scope(), payload: payload, clientMessageID: String(repeating: "c", count: 32))
            let fields = try payload.wireFields(approvedOrigins: [])
            wire.body = try JSONSerialization.data(withJSONObject: ["code":200,"data":["found":true,"message":[
                "id":3,"conversationId":9,"senderId":7,"status":0,"msgType":Int(fields["msg_type"]!)!,
                "content":fields["content"]!,"extraJson":fields["extra_json"]!,"clientMessageId":String(repeating:"d",count:32)]]])
            do {
                switch index {
                case 0: _ = try await api.recoverVoice(intent, token: "fixture-token")
                case 1: _ = try await api.recoverFile(intent, token: "fixture-token")
                default: _ = try await api.recoverVideo(intent, token: "fixture-token")
                }
                XCTFail()
            } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
        XCTAssertEqual(wire.requests.count, 3)
    }
    func testNewMediaReviewAlwaysRequiresIndependentWriterCapability() throws {
        let writer = NeighborWriter()
        for durable in [false, true] {
            let store = NeighborStorage()
            let journal = try IMExpandedRecoveryJournal(storage: store, scope: .init(context: context(), conversationID: 9))
            let owner = try IMExpandedCoordinator(scope: scope(), writer: writer, recovery: durable ? journal : nil)
            for payload in try payloads() { XCTAssertFalse(owner.review(.send(try .init(scope: scope(), payload: payload)))) }
            XCTAssertTrue(store.rows.isEmpty)
        }
    }
    func testLegacyRouteRetryStillUsesReadSentAndSameIntent() async throws {
        let writer = NeighborWriter(); let owner = try IMExpandedCoordinator(scope: scope(), writer: writer)
        let intent = try IMOutgoingIntent(scope: scope(), payload: .route(topicID: 11))
        XCTAssertTrue(owner.review(.send(intent))); await owner.confirm(); await owner.retryUnchanged()
        XCTAssertEqual(writer.reads, [intent]); XCTAssertEqual(writer.mutations, [.send(intent), .send(intent)])
    }
    func testLegacyImageAcknowledgesWithoutDurableReceiptContract() async throws {
        let writer = NeighborWriter(); writer.result = .sent(try message(type: 2, content: "https://media.example.test/a.jpg"))
        let owner = try IMExpandedCoordinator(scope: scope(), writer: writer)
        let intent = try IMOutgoingIntent(scope: scope(), payload: .image(URL(string: "https://media.example.test/a.jpg")!))
        XCTAssertTrue(owner.review(.send(intent))); await owner.confirm()
        XCTAssertEqual(owner.visibleState, .acknowledged(try XCTUnwrap(writer.result)))
    }
    func testLegacyReadAndMuteRetriesAreNotSwallowedByDurableRecovery() async throws {
        for mutation in [IMMutation.read(conversationID: 9), .mute(conversationID: 9, muted: true)] {
            let writer = NeighborWriter(); let owner = try IMExpandedCoordinator(scope: scope(), writer: writer)
            XCTAssertTrue(owner.review(mutation)); await owner.confirm(); await owner.retryUnchanged()
            XCTAssertEqual(writer.mutations, [mutation, mutation])
        }
    }
    func testOriginalReadCursorDoesNotEnterOrdinaryRecoveryJournal() async throws {
        let store = NeighborStorage(); let writer = NeighborWriter(); writer.result = .read
        let journal = try IMExpandedRecoveryJournal(storage: store, scope: .init(context: context(), conversationID: 9))
        let owner = try IMExpandedCoordinator(scope: scope(), writer: writer, recovery: journal)
        let mutation = IMMutation.readCursor(conversationID: 9, lastMessageID: 41, requestID: "ack-cursor-00000001")
        XCTAssertTrue(owner.review(mutation)); await owner.confirm()
        XCTAssertEqual(owner.visibleState, .acknowledged(.read)); XCTAssertEqual(writer.mutations, [mutation]); XCTAssertTrue(store.rows.isEmpty)
    }
    func testDurableMediaSavesBeforeDispatchAndRestoresWithoutNewRequest() async throws {
        let store = NeighborStorage(); let writer = NeighborWriter(); writer.canSendVoice = true
        let journal = try IMExpandedRecoveryJournal(storage: store, scope: .init(context: context(), conversationID: 9))
        let owner = try IMExpandedCoordinator(scope: scope(), writer: writer, recovery: journal)
        let intent = try IMOutgoingIntent(scope: scope(), payload: payloads()[0], clientMessageID: String(repeating: "c", count: 32))
        writer.beforePerform = { XCTAssertEqual(try? journal.restore(current: self.scope()), .send(intent)) }
        XCTAssertTrue(owner.review(.send(intent))); await owner.confirm()
        let bytes = store.rows
        let reentered = try IMExpandedCoordinator(scope: scope(), writer: writer, recovery: journal)
        XCTAssertEqual(reentered.visibleState, .outcomeUnknown(.send(intent))); XCTAssertEqual(store.rows, bytes); XCTAssertEqual(writer.mutations.count, 1)
    }
    func testLegacyImageMissingJournalCannotBecomeLocallyApplied() async throws {
        let store = NeighborStorage(), writer = NeighborWriter()
        let journal = StoredImageUploadJournal(read: { store.rows[$0] }, write: { store.rows[$1] = $0 })
        let target = try ImageUploadTarget(accountID: 7, namespace: "CN:host-test", realm: "https://api.example.test", kind: "im", entityID: 9, field: "image")
        let selection = try IMMediaSelection(scope: scope(), bytes: Data([255,216,255]), mimeType: "image/jpeg", fileExtension: "jpg")
        let url = URL(string: "https://media.example.test/a.jpg")!; writer.uploadResult = url
        let owner = try IMImageUploadCoordinator(scope: scope(), writer: writer, picker: IMFixtureImagePicker(selection: selection), journal: journal, target: target)
        await owner.selectAfterConsent(); await owner.uploadAfterConsent()
        XCTAssertEqual(owner.visibleState, .uploaded(url)); store.rows.removeAll()
        XCTAssertFalse(owner.applyLocally(url, consume: { _ in true }))
        XCTAssertEqual(owner.visibleState, .outcomeUnknown)
    }
    private func message(type: Int, content: String) throws -> MessagingMessage {
        try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject:
            ["id":3,"conversationId":9,"senderId":7,"status":0,"msgType":type,"content":content]))
    }
    private func config(_ routes: [BusinessRuntimeFeature:Set<BusinessRuntimeRoute>], origins: Set<String> = []) throws -> BusinessRuntimeConfiguration {
        let c = try context()
        return try .init(market: c.market, baseURL: c.baseURL, namespace: c.session.namespace, accountID: 7, routes: routes, imMediaOrigins: origins)
    }
    private func request(path: String = "api/im/send", method: String = "POST") throws -> URLRequest {
        var r = URLRequest(url: try context().baseURL.appendingPathComponent(path)); r.httpMethod = method
        r.httpShouldHandleCookies = false; r.setValue("fixture-token", forHTTPHeaderField: "Authorization"); return r
    }
    func testPerFeatureWithdrawalRetiresEvenWhenRouteUnionIsUnchanged() async throws {
        let route = try BusinessRuntimeRoute.post("api/im/send")
        let issued = try config([.imSend:[route], .imVoiceSend:[route]])
        var live = issued; let wire = NeighborWire(); let c = try context()
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imSend,.imVoiceSend],underlying:wire,runtime:{c},configuration:{live},presentation:{true}))
        live = try config([.imSend:[route]])
        XCTAssertFalse(gate.isCurrent)
        live = issued; XCTAssertFalse(gate.isCurrent)
        do { _ = try await gate.send(request()); XCTFail() } catch { }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testObservedMissingConfigurationCannotReviveOldIssuanceAfterRegrant() throws {
        let issued = try config([.imVoiceSend:[.post("api/im/send")]])
        var live: BusinessRuntimeConfiguration? = issued; let c = try context()
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imVoiceSend],underlying:NeighborWire(),runtime:{c},configuration:{live},presentation:{true}))
        live = nil; XCTAssertFalse(gate.isCurrent)
        live = issued; XCTAssertFalse(gate.isCurrent)
        let replacement = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imVoiceSend],underlying:NeighborWire(),runtime:{c},configuration:{live},presentation:{true}))
        XCTAssertTrue(replacement.isCurrent); XCTAssertFalse(gate.isCurrent)
    }
    func testOriginWithdrawalPermanentlyRetiresConsumer() throws {
        let route = try BusinessRuntimeRoute.post("api/im/send")
        let issued = try config([.imFileSend:[route]], origins:["https://media.example.test"])
        var live = issued; let c = try context()
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imFileSend],underlying:NeighborWire(),runtime:{c},configuration:{live},presentation:{true}))
        live = try config([.imFileSend:[route]])
        XCTAssertFalse(gate.isCurrent); live = issued; XCTAssertFalse(gate.isCurrent)
    }
    func testLate401AfterPresentationRetirementIsNotReturned() async throws {
        let issued = try config([.imVoiceReceipt:[.post("api/im/send-receipt")]])
        let c = try context(); var active = true; let wire = NeighborWire(); wire.status = 401; wire.beforeReturn = { active = false }
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imVoiceReceipt],underlying:wire,runtime:{c},configuration:{issued},presentation:{active}))
        do { _ = try await gate.send(request(path:"api/im/send-receipt")); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(gate.isCurrent); XCTAssertEqual(wire.requests.count,1)
    }
    func testEmptyMediaRoutesCanRetainSidecarButCannotDispatch() async throws {
        let issued = try config([:]); let c = try context(); let wire = NeighborWire()
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imVoiceUpload],underlying:wire,runtime:{c},configuration:{issued},presentation:{true}))
        XCTAssertTrue(gate.isCurrent)
        do { _ = try await gate.send(request(path:"api/im/voice/upload")); XCTFail() } catch { }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testFinalForwardRejectsWrongMethodTokenOriginAndCookies() async throws {
        let issued = try config([.imFileSend:[.post("api/im/send")]]); let c = try context(); let wire = NeighborWire()
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imFileSend],underlying:wire,runtime:{c},configuration:{issued},presentation:{true}))
        var wrongMethod = try request(); wrongMethod.httpMethod = "GET"
        var wrongToken = try request(); wrongToken.setValue("foreign", forHTTPHeaderField:"Authorization")
        var wrongOrigin = try request(); wrongOrigin.url = URL(string:"https://elsewhere.test/api/im/send")
        var cookies = try request(); cookies.httpShouldHandleCookies = true
        var cookieHeader = try request(); cookieHeader.setValue("session=foreign", forHTTPHeaderField:"Cookie")
        for request in [wrongMethod,wrongToken,wrongOrigin,cookies,cookieHeader] {
            do { _ = try await gate.send(request); XCTFail() } catch { }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEpochChangePermanentlyRetiresConsumer() throws {
        let issued = try config([.imVideoSend:[.post("api/im/send")]]); let c = try context(); var live = c
        let gate = try XCTUnwrap(NativeChannelHostRuntimeTransport(context:c,issued:issued,features:[.imVideoSend],underlying:NeighborWire(),runtime:{live},configuration:{issued},presentation:{true}))
        live = try context(epoch:2); XCTAssertFalse(gate.isCurrent); live = c; XCTAssertFalse(gate.isCurrent)
    }
    func testIndependentMediaCatalogNeverAcceptsGenericUploadOrWrongMethod() throws {
        for feature in [BusinessRuntimeFeature.imVoiceUpload,.imFileUpload,.imVideoUpload] {
            XCTAssertFalse(feature.accepts(try .post("api/common/uploadOSS")))
            XCTAssertFalse(feature.accepts(try .post("api/im/send")))
        }
        XCTAssertFalse(BusinessRuntimeFeature.imVoiceReceipt.accepts(try .init(method:"GET",path:"api/im/send-receipt")))
        XCTAssertFalse(BusinessRuntimeFeature.imCheckinWrite.accepts(try .init(method:"GET",path:"api/im/channel/checkin")))
    }
}
@MainActor private final class NeighborWire: HTTPTransport {
    var requests: [URLRequest] = []
    var body = Data(#"{"code":200,"data":{"found":false}}"#.utf8)
    var status = 200
    var beforeReturn: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); beforeReturn?(); return (body,status) }
}
@MainActor private final class NeighborStorage: ProjectEditDataStorage {
    var rows: [String:Data] = [:]
    func read(_ key:String) throws -> Data? { rows[key] }
    func write(_ data:Data,key:String) throws { rows[key]=data }
    func remove(_ key:String) throws { rows[key]=nil }
}
@MainActor private final class NeighborWriter: IMExpandedWriting, IMSentReading {
    var identity: MessagingReadIdentity? = .init(accountID:7,epoch:1)
    var isConfigured = true
    var canSendVoice = false
    var mutations: [IMMutation] = []
    var reads: [IMOutgoingIntent] = []
    var result: IMMutationReceipt?
    var uploadResult: URL?
    var beforePerform: (() -> Void)?
    func perform(_ mutation:IMMutation,expectedIdentity:MessagingReadIdentity) async throws -> IMMutationReceipt {
        beforePerform?(); mutations.append(mutation); if let result { return result }; throw URLError(.timedOut)
    }
    func readSent(_ intent:IMOutgoingIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage? { reads.append(intent); return nil }
    func upload(_ selection:IMMediaSelection,consent:IMMediaConsent,expectedIdentity:MessagingReadIdentity) async throws -> URL { if let uploadResult { return uploadResult }; throw APIError.notConfigured }
}
