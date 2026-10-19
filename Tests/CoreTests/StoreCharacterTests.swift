import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class StoreCharacterTestTransport: HTTPTransport {
    struct Offline: Error {}
    var replies: [String: (Data, Int)] = [:]
    var failing: Set<String> = []
    var onSend: ((String) -> Void)?
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = String((request.url?.path ?? "").drop(while: { $0 == "/" }))
        onSend?(path)
        if failing.contains(path) { throw Offline() }
        return replies[path] ?? (Data(#"{"code":404}"#.utf8), 404)
    }
    func set(_ path: String, _ json: String, status: Int = 200) { replies[path] = (Data(json.utf8), status) }
    func body(_ index: Int) -> [String: Any] {
        (requests[index].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }
}

@MainActor final class StoreCharacterTests: XCTestCase {
    private let access = #"{"code":200,"data":{"active":true,"merchant":{"id":31,"name":"Sample"},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}}"#
    private func backend(_ transport: StoreCharacterTestTransport, gates: MerchantCityNPCParityGates = .disabled,
                         execution: StoreCharacterServiceBackend.Execution = .disabled, scope: @escaping () -> UUID?) -> StoreCharacterServiceBackend {
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com/")!)
        return StoreCharacterServiceBackend(service: .init(configuration: configuration, transport: transport), market: .china,
                                            gates: gates, execution: execution, token: { "synthetic-token" }, currentScope: scope)
    }
    private var saveGates: MerchantCityNPCParityGates { var g = MerchantCityNPCParityGates(); g.storeCharacterSaves = true; return g }

    func testPayloadTrimsWithJavaScriptWhitespaceAndSendsExactlyFiveKeys() throws {
        let payload = StoreCharacterSavePayload(name: "\u{3000} Host \n", greeting: " Hi ", persona: "", knowledge: "\u{FEFF}Menu", avatar: "px1:p07")
        XCTAssertEqual(payload.name, "Host"); XCTAssertEqual(payload.knowledge, "Menu")
        let json = try JSONSerialization.jsonObject(with: payload.jsonBody()) as? [String: String]
        XCTAssertEqual(Set(json.map { Array($0.keys) } ?? []), ["name", "greeting", "persona", "knowledge", "avatar"])
        XCTAssertEqual(json?["persona"], "")
    }
    func testBlockersFollowSourceLimitsInUTF16Units() {
        XCTAssertEqual(StoreCharacterField.allCases.map(\.limit), [32, 60, 500, 2000])
        XCTAssertEqual(StoreCharacterSavePayload(name: " ", greeting: "", persona: "", knowledge: "", avatar: "px1:p01").blocker, .nameRequired)
        XCTAssertEqual(StoreCharacterSavePayload(name: String(repeating: "😀", count: 17), greeting: "", persona: "", knowledge: "", avatar: "px1:p01").blocker, .nameTooLong)
        XCTAssertEqual(StoreCharacterSavePayload(name: "A", greeting: String(repeating: "a", count: 61), persona: "", knowledge: "", avatar: "px1:p01").blocker, .greetingTooLong)
        XCTAssertEqual(StoreCharacterSavePayload(name: "A", greeting: "", persona: "", knowledge: "", avatar: "").blocker, .avatarRequired)
        XCTAssertEqual(StoreCharacterSavePayload(name: "A", greeting: "", persona: "", knowledge: "", avatar: "px1:p99").blocker, .avatarUnsupported)
        XCTAssertEqual(StoreCharacterText.clamp("ab😀c", limit: 3), "ab")
    }
    func testAvatarCodesMirrorServerAllowList() {
        XCTAssertEqual(StoreCharacterAvatar.presetIDs, ["p01", "p04", "p07", "p10", "p13", "p17", "p18", "p23", "p25", "p27", "p31", "p36"])
        XCTAssertEqual(StoreCharacterAvatar(code: "px1:p23"), .preset("p23"))
        XCTAssertEqual(StoreCharacterAvatar(code: "https://example.com/a.png"), .photo("https://example.com/a.png"))
        XCTAssertNil(StoreCharacterAvatar(code: "px1:p02"))
        XCTAssertNil(StoreCharacterAvatar(code: "javascript:alert(1)"))
    }
    func testProfileNullIsEmptyAndBadgeOnlyWithProfile() async throws {
        let transport = StoreCharacterTestTransport()
        transport.set(StoreCharacterEndpoint.profile, #"{"code":200,"data":null}"#)
        let reader = backend(transport, scope: { UUID(uuidString: "00000000-0000-0000-0000-000000000001") })
        let empty = try await reader.profile()
        XCTAssertFalse(empty.hasProfile); XCTAssertNil(empty.badge)
        transport.set(StoreCharacterEndpoint.profile, #"{"code":"200","data":{"name":"A","avatar":"px1:p01","auditStatus":"2","auditReason":"R","voiceStatus":1}}"#)
        let rejected = try await reader.profile()
        XCTAssertEqual(rejected.badge, .rejected); XCTAssertEqual(rejected.rejectionReason, "R"); XCTAssertEqual(rejected.voiceStatus, 1)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/merchant/npc/profile")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testVoiceStatusDecodesTopLevelOnly() async throws {
        let transport = StoreCharacterTestTransport()
        let reader = backend(transport, scope: { UUID(uuidString: "00000000-0000-0000-0000-000000000001") })
        transport.set(StoreCharacterEndpoint.voiceStatus, #"{"code":200,"msg":"ok","voiceStatus":2,"voiceSample":"https://example.com/s.mp3"}"#)
        let value = try await reader.voiceStatus()
        XCTAssertEqual(value, .init(status: .ready, sample: "https://example.com/s.mp3"))
        transport.set(StoreCharacterEndpoint.voiceStatus, #"{"code":200,"data":{"voiceStatus":2}}"#)
        do { _ = try await reader.voiceStatus(); XCTFail() } catch { XCTAssertEqual(error as? StoreCharacterFailure, .malformed) }
        transport.set(StoreCharacterEndpoint.voiceStatus, #"{"code":200,"voiceStatus":7}"#)
        do { _ = try await reader.voiceStatus(); XCTFail() } catch { XCTAssertEqual(error as? StoreCharacterFailure, .malformed) }
    }
    func testMapPointJudgesCoordinatesNotAddress() throws {
        let decode = { (json: String) in try JSONDecoder().decode(StoreCharacterMapPointState.self, from: Data(json.utf8)) }
        XCTAssertFalse(try decode(#"{"address":"Sample","locationLat":null,"locationLng":null}"#).hasPoint)
        XCTAssertFalse(try decode(#"{"address":"Sample","locationLat":"","locationLng":1}"#).hasPoint)
        let point = try decode(#"{"address":"","locationLat":1.5,"locationLng":"2"}"#)
        XCTAssertTrue(point.hasPoint); XCTAssertNil(point.displayAddress)
    }
    func testConsentAndEnrollmentBodies() throws {
        let id = UUID()
        let record = StoreCharacterVoiceConsentRecord(requestID: id)
        XCTAssertEqual(record.fields["docType"], "voice_clone_processing"); XCTAssertEqual(record.fields["scene"], "merchant_voice")
        XCTAssertEqual(record.fields["eventType"], "AGREE"); XCTAssertLessThanOrEqual(record.requestID.count, 64)
        XCTAssertEqual(record, StoreCharacterVoiceConsentRecord(requestID: id))
        let row = try JSONDecoder().decode(StoreCharacterConsentRow.self, from: Data(#"{"requestId":"\#(record.requestID)","docType":"voice_clone_processing","scene":"merchant_voice","eventType":"AGREE","docVersion":"1"}"#.utf8))
        XCTAssertTrue(record.accepts(row))
        let enrollment = try XCTUnwrap(StoreCharacterVoiceEnrollment(voiceSample: "https://example.com/v.mp3"))
        let body = try JSONSerialization.jsonObject(with: enrollment.jsonBody()) as? [String: Any]
        XCTAssertEqual(body?["voiceConsent"] as? Bool, true); XCTAssertEqual(body?["voiceSample"] as? String, "https://example.com/v.mp3")
        XCTAssertEqual(Set(body?.keys.map { $0 } ?? []), ["voiceSample", "voiceConsent"])
        XCTAssertNil(StoreCharacterVoiceEnrollment(voiceSample: "file:///tmp/a.mp3"))
        XCTAssertNotNil(StoreCharacterVoiceEnrollment(voiceSample: "media-asset:42"))
        XCTAssertNil(StoreCharacterVoiceEnrollment(voiceSample: "media-asset:0"))
    }
    func testWritesAreDisabledByDefaultAndWithoutAllowlist() async {
        let transport = StoreCharacterTestTransport()
        let off = backend(transport, scope: { UUID() })
        let payload = StoreCharacterSavePayload(name: "A", greeting: "", persona: "", knowledge: "", avatar: "px1:p01")
        do { try await off.save(payload, requestID: UUID()); XCTFail() } catch { XCTAssertEqual(error as? StoreCharacterFailure, .writesDisabled) }
        let gatedButNotReviewed = backend(transport, gates: saveGates, scope: { UUID() })
        XCTAssertFalse(gatedButNotReviewed.permits(StoreCharacterEndpoint.save))
        XCTAssertTrue(MerchantCityNPCParityGates.reviewedEndpoints.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testWriteClassificationRejectedVersusUnknown() async {
        let transport = StoreCharacterTestTransport()
        let scope = UUID()
        let writer = backend(transport, gates: saveGates, execution: .injectedOfflineHarness, scope: { scope })
        let payload = StoreCharacterSavePayload(name: "A", greeting: "", persona: "", knowledge: "", avatar: "px1:p01")
        transport.set(StoreCharacterEndpoint.save, #"{"code":500,"msg":"名字最多 32 个字"}"#)
        do { try await writer.save(payload, requestID: UUID()); XCTFail() } catch { XCTAssertEqual(error as? StoreCharacterFailure, .rejected(code: 500, message: "名字最多 32 个字")) }
        transport.set(StoreCharacterEndpoint.save, "", status: 502)
        do { try await writer.save(payload, requestID: UUID()); XCTFail() } catch { XCTAssertEqual(error as? StoreCharacterFailure, .outcomeUnknown) }
        transport.failing = [StoreCharacterEndpoint.save]
        do { try await writer.save(payload, requestID: UUID()); XCTFail() } catch { XCTAssertEqual(error as? StoreCharacterFailure, .outcomeUnknown) }
    }
    func testFirstFieldSaveCarriesPreviewAvatarAndUnknownReadsBack() async {
        let transport = StoreCharacterTestTransport()
        transport.set(StoreCharacterEndpoint.access, access)
        transport.set(StoreCharacterEndpoint.profile, #"{"code":200,"data":null}"#)
        transport.set(StoreCharacterEndpoint.voiceStatus, #"{"code":200,"voiceStatus":0}"#)
        let scope = UUID()
        let backend = backend(transport, gates: saveGates, execution: .injectedOfflineHarness, scope: { scope })
        let coordinator = StoreCharacterCoordinator(reader: backend, writer: backend, gates: saveGates)
        await coordinator.load()
        XCTAssertEqual(coordinator.phase, .ready); XCTAssertEqual(coordinator.mapPoint, .unset)
        await coordinator.openVoice()
        XCTAssertEqual(coordinator.notice, .saveProfileFirst); XCTAssertFalse(coordinator.voiceVisible)
        coordinator.editField(.greeting); coordinator.updateField("Hello"); coordinator.saveField()
        XCTAssertEqual(coordinator.notice, .nameFirst); XCTAssertEqual(coordinator.field?.field, .name)
        coordinator.updateField(" Host "); coordinator.saveField()
        let confirmation = try? XCTUnwrap(coordinator.saveConfirmation)
        XCTAssertEqual(confirmation?.payload.avatar, "px1:p01"); XCTAssertEqual(confirmation?.payload.greeting, "Hello")
        transport.failing = [StoreCharacterEndpoint.save]
        transport.set(StoreCharacterEndpoint.profile, #"{"code":200,"data":{"name":"Host","avatar":"px1:p01","greeting":"Hello","persona":"","knowledge":"","auditStatus":0}}"#)
        if let id = confirmation?.id { await coordinator.confirmSave(id) }
        XCTAssertEqual(coordinator.notice, .readbackConfirmed); XCTAssertFalse(coordinator.saveLocked)
        XCTAssertTrue(coordinator.saved.hasProfile); XCTAssertEqual(coordinator.saved.badge, .reviewing)
        XCTAssertEqual(transport.requests.filter { $0.url?.path == "/api/merchant/npc/save" }.count, 1)
    }
    func testExistingProfileFieldSaveUsesSavedAvatarAndReusesRequestID() async {
        let transport = StoreCharacterTestTransport()
        transport.set(StoreCharacterEndpoint.access, access)
        transport.set(StoreCharacterEndpoint.profile, #"{"code":200,"data":{"name":"Host","avatar":"https://example.com/a.png","greeting":"Hi","auditStatus":1}}"#)
        transport.set(StoreCharacterEndpoint.save, #"{"code":500,"msg":"Sample rejection"}"#)
        let scope = UUID()
        let backend = backend(transport, gates: saveGates, execution: .injectedOfflineHarness, scope: { scope })
        let coordinator = StoreCharacterCoordinator(reader: backend, writer: backend, gates: saveGates)
        await coordinator.load()
        coordinator.editField(.knowledge); coordinator.updateField("Menu"); coordinator.saveField()
        guard let first = coordinator.saveConfirmation else { return XCTFail() }
        XCTAssertEqual(first.payload.avatar, "https://example.com/a.png"); XCTAssertEqual(first.payload.name, "Host")
        await coordinator.confirmSave(first.id)
        XCTAssertEqual(coordinator.saveIssue, .rejected("Sample rejection"))
        coordinator.saveField()
        XCTAssertEqual(coordinator.saveConfirmation?.id, first.id)
    }
    func testDefaultCoordinatorNeverPreparesWrites() async {
        let transport = StoreCharacterTestTransport()
        transport.set(StoreCharacterEndpoint.access, access)
        transport.set(StoreCharacterEndpoint.profile, #"{"code":200,"data":{"name":"Host","avatar":"px1:p01"}}"#)
        let reader = backend(transport, scope: { UUID(uuidString: "00000000-0000-0000-0000-000000000002") })
        let coordinator = StoreCharacterCoordinator(reader: reader, writer: reader)
        await coordinator.load()
        coordinator.editField(.name); coordinator.updateField("Other"); coordinator.saveField()
        XCTAssertNil(coordinator.saveConfirmation); XCTAssertEqual(coordinator.notice, .writesDisabled)
        coordinator.chooseStorePoint(); XCTAssertEqual(coordinator.notice, .mapPointUnavailable)
        XCTAssertFalse(coordinator.showsReformScopes)
    }
    func testDeniedRoleAndStaleCompletionAreDropped() async {
        let transport = StoreCharacterTestTransport()
        transport.set(StoreCharacterEndpoint.access, #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_CHECKIN","permissions":["merchant:basic:read"]}}"#)
        let reader = backend(transport, scope: { UUID() })
        let coordinator = StoreCharacterCoordinator(reader: reader)
        await coordinator.load()
        XCTAssertEqual(coordinator.phase, .denied(.missingPermission))
        var current: UUID? = UUID()
        let rotating = backend(transport, scope: { current })
        transport.set(StoreCharacterEndpoint.access, access)
        let stale = StoreCharacterCoordinator(reader: rotating)
        // Account switch while access/me is in flight: the completion must not populate the page.
        transport.onSend = { path in if path == StoreCharacterEndpoint.access { current = UUID() } }
        await stale.load()
        XCTAssertNotEqual(stale.phase, .ready)
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/api/merchant/npc/profile" })
    }
    func testKnowledgeIsStorePublicOnly() throws {
        let store = try XCTUnwrap(StoreCharacterKnowledgeIsolation.storePublicScope(merchantID: "m", storeID: "s"))
        XCTAssertTrue(StoreCharacterKnowledgeIsolation.mayReceive(store))
        XCTAssertFalse(StoreCharacterKnowledgeIsolation.mayReceive(.merchantPrivate(merchantID: "m", storeID: "s", operatorID: "o")))
        XCTAssertFalse(StoreCharacterKnowledgeIsolation.mayReceive(.creator(accountID: "a")))
        let binding = try XCTUnwrap(ThemeNPCSessionScope(actorType: .player, actorID: "p", merchantID: "m", themeID: "t", releaseID: "r", runID: "u", bindingID: "b"))
        XCTAssertFalse(StoreCharacterKnowledgeIsolation.mayReceive(.themeBinding(binding)))
        XCTAssertNil(StoreCharacterKnowledgeIsolation.storePublicScope(merchantID: " m", storeID: "s"))
    }
    func testSceneProjectionKeepsModesApartAndHintIsCompareOnly() throws {
        let binding = try XCTUnwrap(ThemeNPCSessionScope(actorType: .team, actorID: "p", merchantID: "m", themeID: "t", releaseID: "r", runID: "u", bindingID: "b"))
        let bound = StoreCharacterSceneProjection(merchantID: "m", storeID: "s", serverBinding: binding, clientThemeHint: "t")
        guard case .bound(let key) = bound.themeBinding else { return XCTFail() }
        XCTAssertNotEqual(key, bound.storePublicKey); XCTAssertFalse(bound.sharesIsolation); XCTAssertFalse(bound.knowledgeReachesTheme)
        XCTAssertEqual(bound.storeMode, .nonGenerative(reasonKey: "sceneAI.unavailable.global"))
        XCTAssertEqual(StoreCharacterSceneProjection(merchantID: "m", storeID: "s", serverBinding: binding, clientThemeHint: "other").themeBinding, .hintMismatch)
        XCTAssertEqual(StoreCharacterSceneProjection(merchantID: "x", storeID: "s", serverBinding: binding, clientThemeHint: nil).themeBinding, .hintMismatch)
        XCTAssertEqual(StoreCharacterSceneProjection(merchantID: "m", storeID: "s", serverBinding: nil, clientThemeHint: "t").themeBinding, .notBound)
    }
    func testAIDraftNeverPublishableFromThisPage() {
        let approval = MerchantAuthoringApproval(authority: .storeOwner, approverID: "owner", approvedHash: "h")
        let revision = MerchantAuthoringRevision(draftID: "d", version: 1, stage: .approved, authorID: "editor", contentHash: "h",
                                                 touchesThemeContent: false, merchantFactsApproval: approval, themeContentApproval: nil)
        var gates = MerchantCityNPCParityGates(); gates.merchantAIDrafts = true
        let status = StoreCharacterAIDraftStatus(revision: revision, gates: gates)
        XCTAssertEqual(status.blockers, [.capabilityDisabled]); XCTAssertFalse(status.canPublish)
        XCTAssertFalse(StoreCharacterAIDraftStatus.publishRouteRegistered)
    }
}
