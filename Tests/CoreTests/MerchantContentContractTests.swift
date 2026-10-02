import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ContentScriptTransport: MerchantContentOfflineTransport {
    var replies: [(String, Int)] = []
    var requests: [URLRequest] = []
    var callback: ((Int) -> Void)?
    var failAt: Int?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); callback?(requests.count)
        if requests.count == failAt { throw URLError(.timedOut) }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let r = replies.removeFirst(); return (Data(r.0.utf8), r.1)
    }
    func append(_ raw: String) { replies.append(("{\"code\":200,\"data\":" + raw + "}", 200)) }
}
final class MerchantContentContractTests: XCTestCase {
    private func value(_ json: String) throws -> MerchantContentValue { try MerchantContentFixtureData.value(json) }
    private func fields(_ c: MerchantContentCommand) throws -> [String: MerchantContentValue] {
        let request = try c.request()
        switch request.body { case .json(let f): return f; case .form(let f): return f.mapValues { .string($0) } }
    }
    private func snapshot(_ query: MerchantContentQuery, _ raw: String) throws -> MerchantContentSnapshot {
        .init(query: query, scope: UUID(), access: try value(MerchantContentFixtureData.access).decoded(MerchantAccess.self), value: try value(raw), observedAt: Date())
    }
    func testJSONBooleanNeverBecomesID() throws { XCTAssertNil(try value("true").integer); XCTAssertNil(try value("1.5").integer) }
    func testGameIDsRejectStringsAndUnsafeIntegers() throws { XCTAssertNil(try value(#""12""#).safeInteger); XCTAssertNil(try value("9007199254740992").safeInteger) }
    func testApplicationWithdrawUsesApplicationID() throws { XCTAssertEqual(try fields(.withdraw(applicationID: 9)), ["applicationId": .integer(9)]) }
    func testApplicationMessageIsTrimmedAndOmittedWhenEmpty() throws {
        XCTAssertEqual(try fields(.apply(chapterID: 7, message: "  ")), ["chapterId": .integer(7)])
        XCTAssertEqual(try fields(.apply(chapterID: 7, message: " hi "))["message"], .string("hi"))
    }
    func testInviteKeepsMemberAndMerchantIDsDistinct() throws {
        let f = try fields(.invite(chapterID: 7, merchantMemberID: 42))
        XCTAssertEqual(Set(f.keys), ["chapterId", "merchantMemberId"]); XCTAssertEqual(f["merchantMemberId"], .integer(42))
    }
    func testInvitableRequiresExactChapterMemberPair() throws {
        let s = try snapshot(.invitable(topicID: 70), #"[{"chapterId":7,"memberId":42},{"chapterId":8,"memberId":43}]"#)
        XCTAssertNoThrow(try MerchantContentCommand.invite(chapterID: 7, merchantMemberID: 42).validate(against: s))
        XCTAssertThrowsError(try MerchantContentCommand.invite(chapterID: 7, merchantMemberID: 43).validate(against: s))
    }
    func testInvitedOrMissingSourceApplicationCannotWithdraw() throws {
        for raw in [#"[{"id":9,"status":0,"source":1}]"#, #"[{"id":9,"status":0}]"#, #"[{"id":9,"status":1,"source":0}]"#] {
            XCTAssertThrowsError(try MerchantContentCommand.withdraw(applicationID: 9).validate(against: snapshot(.applications, raw)))
        }
    }
    func testRegistrationEditContainsSevenClearableFieldsAndImmutableTopicID() throws {
        var d = MerchantRegistrationContentDraft(detail: try value(MerchantContentFixtureData.registration)); d.picUrl = ""; d.limitNum = ""
        let f = try fields(.updateRegistration(id: 22, topicID: 70, draft: d))
        XCTAssertEqual(Set(f.keys), ["id", "topicId", "picUrl", "address", "addressName", "longitude", "latitude", "activityDesc", "limitNum"])
        XCTAssertEqual(f["picUrl"], .string("")); XCTAssertEqual(f["limitNum"], .integer(0)); XCTAssertNil(f["startDate"]); XCTAssertNil(f["cooperateDate"])
    }
    func testRegistrationCreateOnlyAddsSourceModeNodeAndOptionalCooperateDate() throws {
        let d = MerchantRegistrationContentDraft(detail: try value(MerchantContentFixtureData.registration))
        let f = try fields(.register(topicID: 70, nodeID: 62, draft: d, cooperateDate: "09:00-18:00"))
        XCTAssertEqual(f["mode"], .integer(1)); XCTAssertEqual(f["nodeId"], .integer(62)); XCTAssertEqual(f["cooperateDate"], .string("09:00-18:00")); XCTAssertNil(f["id"])
    }
    func testNegativeOrMalformedCapacityDoesNotSilentlyBecomeUnlimited() throws {
        var d = MerchantRegistrationContentDraft(detail: try value(MerchantContentFixtureData.registration))
        for bad in ["-1", "1.2", "lots"] { d.limitNum = bad; XCTAssertThrowsError(try d.fields()) }
    }
    func testRegistrationUpdateCannotReassignTopicOrUpdateWon() throws {
        let s = try snapshot(.registration(id: 22), MerchantContentFixtureData.registration)
        let d = MerchantRegistrationContentDraft(detail: s.value)
        XCTAssertThrowsError(try MerchantContentCommand.updateRegistration(id: 22, topicID: 71, draft: d).validate(against: s))
        let won = try snapshot(.registration(id: 22), MerchantContentFixtureData.registration.replacingOccurrences(of: #""auditStatus":0"#, with: #""auditStatus":1"#))
        XCTAssertThrowsError(try MerchantContentCommand.updateRegistration(id: 22, topicID: 70, draft: d).validate(against: won))
    }
    func testCancellationNeedsKnownNotWonStatus() throws {
        XCTAssertThrowsError(try MerchantContentCommand.cancelRegistration(id: 22).validate(against: snapshot(.registration(id: 22), #"{"id":22,"status":0}"#)))
    }
    func testChapterDraftOmitsXPAndOwnerModerationFields() throws {
        var d = MerchantChapterContentDraft(); d.name = "A node"; d.templateID = 4
        let f = try d.fields(chapterID: 7)
        XCTAssertNil(f["xpValue"]); XCTAssertNil(f["merchantMemberId"]); XCTAssertNil(f["topicId"]); XCTAssertNil(f["nodeAuditStatus"])
        XCTAssertEqual(f["templateId"], .integer(4))
    }
    func testNodeSubmissionAllowsPendingChainButRequiresOwnedTemplate() throws {
        var d = MerchantChapterContentDraft(); d.name = "A node"; d.templateID = 4
        let s = try snapshot(.nodeAuthoring(chapterID: 7), #"{"applications":[{"id":12,"chapterId":7,"status":0}],"templates":[{"id":4}]}"#)
        XCTAssertNoThrow(try MerchantContentCommand.submitNode(chapterID: 7, draft: d).validate(against: s))
        d.templateID = 5; XCTAssertThrowsError(try MerchantContentCommand.submitNode(chapterID: 7, draft: d).validate(against: s))
    }
    func testNPCUsesOnlyFourFormFieldsIncludingEmptyGreeting() throws {
        let r = try MerchantContentCommand.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: "").request()
        XCTAssertEqual(r.path, "api/merchant/chapter-node/npc/save")
        guard case .form(let f) = r.body else { return XCTFail("Node NPC requires multipart form") }
        XCTAssertEqual(f, ["nodeId": "62", "name": "Guide", "avatar": "asset", "greeting": ""])
    }
    func testNodeVoiceUsesSingleVoiceSampleNotStoreSampleArray() throws {
        XCTAssertEqual(try fields(.enrollVoice(nodeID: 62, voiceSample: "one-reference")), ["nodeId": .string("62"), "voiceSample": .string("one-reference")])
        XCTAssertEqual(try fields(.resetVoice(nodeID: 62)), ["nodeId": .string("62")])
    }
    func testNodeAuditBoolIsFormString() throws {
        XCTAssertEqual(try fields(.auditNode(nodeID: 62, approve: false, reason: "Not eligible")), ["nodeId": .string("62"), "approve": .string("false"), "reason": .string("Not eligible")])
    }
    func testPlacementMustConfirmAddressButMayUseServerProfileFallback() throws {
        var d = MerchantCityPlacementDraft(); d.templateID = 4
        XCTAssertThrowsError(try d.fields()); d.addressConfirmed = true
        XCTAssertEqual(try d.fields(), ["templateId": "4", "radius": "80"])
        d.latitude = "40"; XCTAssertThrowsError(try d.fields()); d.longitude = "-70"; XCTAssertNotNil(try d.fields()["lat"])
    }
    func testClaimCancellationNeverAliasesApplicationIDToPOIID() throws {
        let s = try snapshot(.city, #"{"applications":[{"id":91,"applicationType":2,"auditStatus":0}]}"#)
        XCTAssertThrowsError(try MerchantContentCommand.cancelClaim(poiID: 91).validate(against: s))
    }
    func testClaimQuotaBlocksBeforeSend() throws {
        let s = try snapshot(.claimable(keyword: ""), #"{"rows":[{"poiId":18}],"catalog":{"used":2,"max":2}}"#)
        XCTAssertThrowsError(try MerchantContentCommand.claim(poiID: 18).validate(against: s))
    }
    func testRecruitModeUsesServerMessageNotProductType() {
        XCTAssertEqual(MerchantRecruitMode.fromServer("仅自由探索支持此入口"), .registration)
        XCTAssertEqual(MerchantRecruitMode.fromServer("请先配置品类"), .categoryMissing)
        XCTAssertEqual(MerchantRecruitMode.fromServer("仅商家可用"), .notMerchant)
        XCTAssertNil(MerchantRecruitMode.fromServer("Network failure"))
    }
    func testSupplyBridgeNeedsMatchingKnownTermsAndCorrectOfferID() throws {
        let a = try value(#"{"id":12,"chapterId":7,"status":1,"offerActive":false,"termsMode":"PERK"}"#)
        XCTAssertFalse(try MerchantContentSupplyContext(application: a, recruitmentChapters: []).canEnroll)
        let c = try value(#"{"id":7,"recruitStatus":{"termsMode":"TRAFFIC"}}"#)
        XCTAssertTrue(try MerchantContentSupplyContext(application: a, recruitmentChapters: [c]).canEnroll)
        let active = try value(#"{"id":12,"chapterId":7,"status":1,"offerActive":1,"offerId":99,"circleThemeCode":"CIRCLE"}"#)
        let bridge = try MerchantContentSupplyContext(application: active, recruitmentChapters: [c])
        XCTAssertEqual(bridge.offerID, 99); XCTAssertTrue(bridge.canReconfirmOrPause); XCTAssertFalse(bridge.canEnroll)
    }
    func testStationActionUnionCannotAuthorizeAnotherStationState() throws {
        let p = try MerchantStationProjection(value(MerchantContentFixtureData.projection))
        XCTAssertTrue(p.allows(.ready, nodeID: 62)); XCTAssertFalse(p.allows(.accept, nodeID: 62)); XCTAssertFalse(p.allows(.ready, nodeID: 61))
    }
    func testStationPerspectiveAndIdentityAreStrict() throws {
        XCTAssertThrowsError(try MerchantStationProjection(value(MerchantContentFixtureData.projection.replacingOccurrences(of: "MERCHANT", with: "PLAYER"))))
        XCTAssertThrowsError(try MerchantStationProjection(value(MerchantContentFixtureData.projection.replacingOccurrences(of: #""sessionId":90"#, with: #""sessionId":"90""#))))
    }
    func testStationDuplicateChecklistRejectsProjection() throws {
        let raw = MerchantContentFixtureData.projection.replacingOccurrences(of: #"{"code":"KIT","label":"Prepare the kit","checked":false}"#, with: #"{"code":"KIT","label":"One","checked":false},{"code":"KIT","label":"Two","checked":true}"#)
        XCTAssertThrowsError(try MerchantStationProjection(value(raw)))
    }
    func testReadyChecksExactChecklistAndCivilTimeOrder() throws {
        let p = try MerchantStationProjection(value(MerchantContentFixtureData.projection))
        let f: [String: MerchantContentValue] = ["capacity": .integer(4), "serviceStartAt": .string("2026-10-02 10:00"), "serviceEndAt": .string("2026-10-02 12:00"), "note": .string(""), "checklist": .array([.object(["code": .string("KIT"), "checked": .bool(true)])])]
        let c = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .ready, payload: f)
        XCTAssertNoThrow(try c.validate(projection: p))
        var bad = f; bad["checklist"] = .array([.object(["code": .string("OTHER"), "checked": .bool(true)])])
        XCTAssertThrowsError(try MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .ready, payload: bad).validate(projection: p))
    }
    func testCivilDatesDoNotNormalizeImpossibleDays() {
        XCTAssertTrue(MerchantStationCommand.validTime("2028-02-29 10:00")); XCTAssertFalse(MerchantStationCommand.validTime("2026-02-29 10:00"))
        XCTAssertFalse(MerchantStationCommand.validTime("2026-10-02T10:00Z")); XCTAssertFalse(MerchantStationCommand.validTime("2026-10-02 24:00"))
    }
    func testStationAcceptCannotSmugglePayload() {
        XCTAssertThrowsError(try MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .accept, payload: ["merchantId": .integer(31)]).fields())
    }
    func testVerificationSubmissionStaysStringAndRejectNeedsReasonCode() throws {
        let c = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .verify, payload: ["submissionId": .string("9223372036854775807"), "decision": .string("APPROVE")])
        XCTAssertNoThrow(try c.fields())
        XCTAssertThrowsError(try MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .verify, payload: ["submissionId": .string("1"), "decision": .string("REJECT")]).fields())
    }
    func testStationReceiptMustCorrelateAllIdentityFieldsAndBeTerminal() throws {
        let c = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, requestID: "frozen-request", action: .ready, payload: [:])
        let raw = #"{"activityId":80,"requestId":"frozen-request","action":"STATION_READY","outcome":"APPLIED","receiptId":77,"revision":4}"#
        XCTAssertEqual(try MerchantStationReceipt(value(raw), command: c).outcome, "APPLIED")
        for modified in [raw.replacingOccurrences(of: "frozen-request", with: "other-request"), raw.replacingOccurrences(of: "APPLIED", with: "PENDING"), raw.replacingOccurrences(of: #""receiptId":77"#, with: #""receiptId":0"#)] {
            XCTAssertThrowsError(try MerchantStationReceipt(value(modified), command: c))
        }
    }
    func testLiveCodeRequiresConfiguredStationAndPlayable() throws { XCTAssertFalse(try MerchantStationProjection(value(MerchantContentFixtureData.projection)).allowsLiveCode(nodeID: 62)) }
}

@MainActor final class MerchantContentServiceTests: XCTestCase {
    private final class SessionBox {
        var value: MerchantContentSession? = try? .init(accountID: 1, epoch: 1, storageScope: "test-realm", token: "synthetic-token")
    }
    private func service(_ t: any HTTPTransport, box: SessionBox, journal: (any MerchantContentPendingStorage)? = nil, enabled: Bool = false, unauthorized: @escaping (MerchantContentSession) -> Void = { _ in }) throws -> MerchantContentService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://merchant-content.example")!), transport: t, currentSession: { box.value }, journal: journal, execution: enabled ? .injectedOfflineHarness : .disabled, onUnauthorized: unauthorized)
    }
    private func failure<T>(_ expected: MerchantContentFailure, _ f: () async throws -> T) async {
        do { _ = try await f(); XCTFail("Expected \(expected)") } catch { XCTAssertEqual(error as? MerchantContentFailure, expected) }
    }
    func testDefaultFactoryRejectsMutationBeforeAnyTransport() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access); t.append("null")
        let s = try service(t, box: box); let baseline = try await s.load(.npc(nodeID: 62))
        await failure(.disabled) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: baseline) }
        XCTAssertEqual(t.requests.count, 2)
    }
    func testEveryReadRechecksFreshAccessAndRevocationStopsDataFetch() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access); t.append("[]"); t.append(#"{"active":false,"permissions":[]}"#)
        let s = try service(t, box: box); _ = try await s.load(.applications)
        await failure(.denied) { try await s.load(.applications) }
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/chapter-application/mine", "/api/merchant/access/me"])
    }
    func testOwnerRoleWithoutProjectsPermissionCannotReadContent() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access.replacingOccurrences(of: #""merchant:project:manage","merchant:marketing:read""#, with: ""))
        let s = try service(t, box: box)
        await failure(.denied) { try await s.load(.projects) }; XCTAssertEqual(t.requests.count, 1)
    }
    func testRegistrationDetailUsesPOSTQueryNotJSONOrForm() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access); t.append(MerchantContentFixtureData.registration)
        _ = try await service(t, box: box).load(.registration(id: 22))
        let request = try XCTUnwrap(t.requests.last); XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.query, "id=22"); XCTAssertNil(request.httpBody)
    }
    func testProjectListCarriesMerchantScopeButWorkspaceDoesNotInventScope() async throws {
        let t = ContentScriptTransport(), box = SessionBox()
        for data in [#"{"rows":[],"total":0}"#, #"{"host":{}}"#] { t.append(MerchantContentFixtureData.access); t.append(data) }
        let s = try service(t, box: box); _ = try await s.load(.projects); _ = try await s.load(.project(topicID: 70))
        XCTAssertTrue(String(decoding: t.requests[1].httpBody!, as: UTF8.self).contains("MERCHANT"))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: t.requests[3].httpBody!), ["topicId": 70])
    }
    func testNPCNullIsValidUnconfiguredAndMultipartRead() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access); t.append("null")
        let v = try await service(t, box: box).load(.npc(nodeID: 62))
        XCTAssertEqual(v.value, .null); XCTAssertTrue(t.requests[1].value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        XCTAssertTrue(String(decoding: t.requests[1].httpBody!, as: UTF8.self).contains("nodeId"))
    }
    func testWrongRegistrationIdentityFailsClosed() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access); t.append(#"{"id":23}"#)
        let s = try service(t, box: box); await failure(.malformed) { try await s.load(.registration(id: 22)) }
    }
    func testSourceModeFallbackAndInvertedRegistrationLookup() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access)
        t.append(#"{"name":"Route","chaptersList":[]}"#)
        t.replies.append((#"{"code":500,"msg":"仅自由探索支持章节招商"}"#, 200))
        t.replies.append((#"{"code":500,"msg":"您已报名此主题，请勿重复报名"}"#, 200))
        let result = try await service(t, box: box).load(.chapters(topicID: 70))
        XCTAssertEqual(result.value["mode"].text, "registration"); XCTAssertEqual(result.value["registered"].flag, true)
    }
    func testRegistrationLookupNetworkFailureRemainsUnknown() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access); t.append(#"{"name":"Route"}"#)
        t.replies.append((#"{"code":500,"msg":"仅自由探索支持章节招商"}"#, 200)); t.failAt = 4
        let result = try await service(t, box: box).load(.chapters(topicID: 70))
        XCTAssertNil(result.value["registered"].flag)
    }
    func testFreshBaselineChangeStopsDormantWrite() async throws {
        let t = ContentScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        t.append(MerchantContentFixtureData.access); t.append("null"); t.append(MerchantContentFixtureData.access); t.append(#"{"name":"Someone else edited"}"#)
        let s = try service(t, box: box, journal: journal, enabled: true); let baseline = try await s.load(.npc(nodeID: 62))
        await failure(.conflict) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: baseline) }
        XCTAssertEqual(t.requests.count, 4); XCTAssertTrue(try journal.records().isEmpty)
    }
    func testEpochChangeCannotReuseIdenticalOldReview() async throws {
        let t = ContentScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        for _ in 0..<2 { t.append(MerchantContentFixtureData.access); t.append("null") }
        let s = try service(t, box: box, journal: journal, enabled: true); let baseline = try await s.load(.npc(nodeID: 62))
        box.value = try .init(accountID: 1, epoch: 2, storageScope: "test-realm", token: "new-synthetic-token")
        await failure(.conflict) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: baseline) }
        XCTAssertEqual(t.requests.count, 4)
    }
    func testAccountSwitchDuringResponseDiscardsOldUnauthorizedWithoutLoggingOutNewAccount() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); var loggedOut = false
        t.append(MerchantContentFixtureData.access); t.replies.append((#"{"code":401}"#, 200))
        t.callback = { count in if count == 2 { box.value = try? .init(accountID: 2, epoch: 2, storageScope: "test-realm", token: "other-token") } }
        let s = try service(t, box: box, unauthorized: { _ in loggedOut = true })
        await failure(.changedSession) { try await s.load(.applications) }; XCTAssertFalse(loggedOut)
    }
    func testWriteTimeoutPersistsUnknownAndReloadCannotClearIt() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal, enabled: true); let b = try await s.load(.npc(nodeID: 62)); t.unknownWrite = true
        await failure(.unknown) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: b) }
        XCTAssertEqual(try s.pending().count, 1)
        let fresh = try await s.load(.npc(nodeID: 62))
        await failure(.locked) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: fresh) }
        XCTAssertEqual(t.requests.filter { $0.url?.path.hasSuffix("npc/save") == true }.count, 1)
    }
    func testOrdinaryBusinessRejectionClearsJournalAndKeepsServerMessage() async throws {
        let t = ContentScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        for _ in 0..<2 { t.append(MerchantContentFixtureData.access); t.append("null") }
        t.replies.append((#"{"code":500,"msg":"承接已失效或未生效,不能编辑节点内容"}"#, 200))
        let s = try service(t, box: box, journal: journal, enabled: true); let b = try await s.load(.npc(nodeID: 62))
        await failure(.rejected(code: 500, message: "承接已失效或未生效,不能编辑节点内容")) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: b) }
        XCTAssertTrue(try s.pending().isEmpty)
    }
    func testGameWriteReadsReceiptAndDoesNotTreatCommandHTTP200AsApplied() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal, enabled: true); let b = try await s.load(.game(activityID: 80))
        let f: [String: MerchantContentValue] = ["capacity": .integer(4), "serviceStartAt": .string("2026-10-02 10:00"), "serviceEndAt": .string("2026-10-02 12:00"), "note": .string(""), "checklist": .array([.object(["code": .string("KIT"), "checked": .bool(true)])])]
        let result = try await s.perform(.station(.init(activityID: 80, nodeID: 62, expectedRevision: 3, action: .ready, payload: f)), baseline: b)
        XCTAssertEqual(result.station?.outcome, "APPLIED")
        XCTAssertEqual(t.requests.suffix(2).map { $0.url!.path }, ["/api/game/session/command", "/api/game/session/receipt"])
        XCTAssertEqual(t.requests.last?.httpMethod, "GET"); XCTAssertTrue(try s.pending().isEmpty)
    }
    func testFileJournalSurvivesRecreationAndDoesNotContainToken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("pending.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let record = MerchantContentPendingRecord(storageScope: "realm", accountID: 1, merchantID: 31, target: "node:62", action: "saveNPC", station: nil)
        try MerchantContentFilePendingStorage(url: url).insert(record)
        XCTAssertEqual(try MerchantContentFilePendingStorage(url: url).records(), [record])
        XCTAssertFalse(try String(contentsOf: url).contains("synthetic-token"))
        XCTAssertThrowsError(try MerchantContentFilePendingStorage(url: url).insert(record))
    }
    func testCorruptJournalPreventsWrites() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }; try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try MerchantContentFilePendingStorage(url: url).records())
    }
    func testCoordinatorReviewIsImmutableAndCannotBeConfirmedTwice() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal, enabled: true), c = MerchantContentCoordinator(service: s, query: .npc(nodeID: 62))
        await c.load(); c.prepare(.saveNPC(nodeID: 62, name: "Frozen", avatar: "asset", greeting: ""))
        let review = try XCTUnwrap(c.review); await c.confirm(review); await c.confirm(review)
        XCTAssertEqual(t.requests.filter { $0.url?.path.hasSuffix("npc/save") == true }.count, 1)
    }
    func testCoordinatorSuspensionKeepsNavigationSnapshotAndCancelsReview() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox()
        let s = try service(t, box: box, journal: MerchantContentMemoryPendingStorage(), enabled: true)
        let c = MerchantContentCoordinator(service: s, query: .npc(nodeID: 62))
        await c.load(); let snapshot = try XCTUnwrap(c.snapshot)
        c.prepare(.saveNPC(nodeID: 62, name: "Frozen", avatar: "asset", greeting: ""))
        let review = try XCTUnwrap(c.review)
        c.suspend()
        XCTAssertEqual(c.snapshot?.value, snapshot.value); XCTAssertTrue(c.isCurrent)
        XCTAssertNil(c.review); XCTAssertFalse(c.busy)
        await c.confirm(review)
        XCTAssertFalse(t.requests.contains { $0.url?.path.hasSuffix("npc/save") == true })
    }
    func testCoordinatorSuspensionDoesNotReleaseUnknownWriteLock() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox()
        let s = try service(t, box: box, journal: MerchantContentMemoryPendingStorage(), enabled: true)
        let c = MerchantContentCoordinator(service: s, query: .npc(nodeID: 62))
        await c.load(); c.prepare(.saveNPC(nodeID: 62, name: "Frozen", avatar: "asset", greeting: ""))
        t.unknownWrite = true; await c.confirm(try XCTUnwrap(c.review))
        XCTAssertTrue(c.locked); c.suspend(); XCTAssertTrue(c.locked)
        XCTAssertEqual(c.issue, "merchant.content.unknown"); XCTAssertEqual(try s.pending().count, 1)
        await c.load(); c.prepare(.saveNPC(nodeID: 62, name: "Again", avatar: "asset", greeting: ""))
        XCTAssertTrue(c.locked); XCTAssertNil(c.review)
        XCTAssertEqual(t.requests.filter { $0.url?.path.hasSuffix("npc/save") == true }.count, 1)
    }
    func testCoordinatorSuspendedSnapshotCannotOutliveAccountScope() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox()
        let s = try service(t, box: box, journal: MerchantContentMemoryPendingStorage())
        let c = MerchantContentCoordinator(service: s, query: .projects)
        await c.load(); XCTAssertNotNil(c.snapshot); c.suspend()
        box.value = nil; XCTAssertFalse(c.isCurrent)
        c.invalidate(); XCTAssertNil(c.snapshot); XCTAssertNil(c.loadedScope)
    }
    func testCoordinatorCancelledReviewCannotDispatch() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal, enabled: true), c = MerchantContentCoordinator(service: s, query: .npc(nodeID: 62))
        await c.load(); c.prepare(.saveNPC(nodeID: 62, name: "Frozen", avatar: "asset", greeting: ""))
        let review = try XCTUnwrap(c.review); c.cancelReview(); await c.confirm(review)
        XCTAssertFalse(t.requests.contains { $0.url?.path.hasSuffix("npc/save") == true })
    }
}

extension MerchantContentContractTests {
    func testOwnerReviewRejectionRequiresReason() throws {
        XCTAssertThrowsError(try MerchantContentCommand.auditApplication(id: 12, approve: false, reason: " ").request())
        XCTAssertThrowsError(try MerchantContentCommand.auditNode(nodeID: 62, approve: false, reason: "").request())
    }
    func testCircleReviewUsesMerchantScopeAndRequiresHostCircleContext() throws {
        let c = MerchantContentCommand.reviewCircle(topicID: 70, scope: "MERCHANT")
        XCTAssertEqual(try fields(c), ["topicId": .integer(70), "scope": .string("MERCHANT")])
        XCTAssertThrowsError(try c.validate(against: snapshot(.project(topicID: 70), #"{"topic":{"circleThemeCode":"CIRCLE"},"join":{}}"#)))
        XCTAssertNoThrow(try c.validate(against: snapshot(.project(topicID: 70), #"{"topic":{"circleThemeCode":"CIRCLE"},"host":{}}"#)))
    }
    func testAbsentOfferStateCannotBecomeAnEnrollmentGrant() throws {
        let a = try value(#"{"id":12,"chapterId":7,"status":1}"#), chapter = try value(#"{"id":7,"recruitStatus":{"termsMode":"TRAFFIC"}}"#)
        let c = try MerchantContentSupplyContext(application: a, recruitmentChapters: [chapter])
        XCTAssertFalse(c.offerStateKnown); XCTAssertFalse(c.canEnroll)
    }
    func testFailedStationReceiptFiltersInternalFailureText() throws {
        let c = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, requestID: "same-request", action: .ready)
        let raw = try value(#"{"activityId":80,"requestId":"same-request","action":"STATION_READY","outcome":"FAILED","receiptId":77,"revision":4,"result":{"reason":"Exception in service.java SELECT"}}"#)
        let r = try MerchantStationReceipt(raw, command: c); XCTAssertEqual(r.outcome, "FAILED"); XCTAssertNil(r.reason)
    }
}
private final class ContentOrdinaryTransport: HTTPTransport {
    var sent = false
    func send(_ request: URLRequest) async throws -> (Data, Int) { sent = true; throw URLError(.notConnectedToInternet) }
}
@MainActor private final class ContentBrokenStorage: MerchantContentPendingStorage {
    func records() throws -> [MerchantContentPendingRecord] { [] }
    func insert(_ record: MerchantContentPendingRecord) throws { throw MerchantContentFailure.storage }
    func remove(key: String) throws { throw MerchantContentFailure.storage }
}
extension MerchantContentServiceTests {
    func testTestExecutionFlagDoesNotEnableOrdinaryNetworkTransport() throws {
        let t = ContentOrdinaryTransport(), box = SessionBox()
        let s = try service(t, box: box, journal: MerchantContentMemoryPendingStorage(), enabled: true)
        XCTAssertFalse(s.permitsWrites); XCTAssertFalse(t.sent)
    }
    func testStorageFailurePreventsMutationDispatch() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox(), journal = ContentBrokenStorage()
        let s = try service(t, box: box, journal: journal, enabled: true); let b = try await s.load(.npc(nodeID: 62))
        await failure(.storage) { try await s.perform(.saveNPC(nodeID: 62, name: "Guide", avatar: "asset", greeting: ""), baseline: b) }
        XCTAssertFalse(t.requests.contains { $0.url?.path.hasSuffix("npc/save") == true })
    }
    func testUnknownContentHasNoInventedReceiptEndpoint() async throws {
        let t = ContentScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let record = MerchantContentPendingRecord(storageScope: "test-realm", accountID: 1, merchantID: 31, target: "node:62", action: "saveNPC", station: nil)
        try journal.insert(record); let s = try service(t, box: box, journal: journal, enabled: true)
        await failure(.locked) { try await s.reconcile(record) }
        XCTAssertTrue(t.requests.isEmpty); XCTAssertEqual(try journal.records(), [record])
    }
    func testUnknownStationRetryRejectsUnrelatedReceiptWithoutSending() async throws {
        let t = ContentScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let command = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, requestID: "frozen-request", action: .ready)
        let record = MerchantContentPendingRecord(storageScope: "test-realm", accountID: 1, merchantID: 31, target: "game:80", action: "STATION_READY", station: command)
        try journal.insert(record); t.append(MerchantContentFixtureData.access)
        t.append(#"{"activityId":80,"requestId":"unrelated-request","action":"STATION_READY","outcome":"PENDING","revision":3}"#)
        let s = try service(t, box: box, journal: journal, enabled: true)
        await failure(.unknown) { try await s.retryStation(record) }
        XCTAssertEqual(t.requests.count, 2); XCTAssertEqual(try journal.records(), [record])
    }
    func testStationRetryPreservesFrozenBodyAfterCorrelatedPendingRead() async throws {
        let t = ContentScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let f: [String: MerchantContentValue] = ["capacity": .integer(4), "serviceStartAt": .string("2026-10-02 10:00"), "serviceEndAt": .string("2026-10-02 12:00"), "note": .string("frozen-note"), "checklist": .array([.object(["code": .string("KIT"), "checked": .bool(true)])])]
        let command = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, requestID: "frozen-request", action: .ready, payload: f)
        let record = MerchantContentPendingRecord(storageScope: "test-realm", accountID: 1, merchantID: 31, target: "game:80", action: "STATION_READY", station: command)
        try journal.insert(record)
        for raw in [MerchantContentFixtureData.access, #"{"activityId":80,"requestId":"frozen-request","action":"STATION_READY","outcome":"PENDING","revision":3}"#, MerchantContentFixtureData.access, MerchantContentFixtureData.projection, #"{}"#, #"{"activityId":80,"requestId":"frozen-request","action":"STATION_READY","outcome":"APPLIED","receiptId":77,"revision":4}"#] { t.append(raw) }
        let s = try service(t, box: box, journal: journal, enabled: true); let receipt = try await s.retryStation(record)
        XCTAssertEqual(receipt.station?.outcome, "APPLIED")
        let sent = try XCTUnwrap(t.requests.first { $0.url?.path == "/api/game/session/command" })
        XCTAssertEqual(try JSONDecoder().decode([String: MerchantContentValue].self, from: sent.httpBody!), try command.fields())
        XCTAssertTrue(try journal.records().isEmpty)
    }
    func testUnpublishedPlayerProjectionFallsBackToMerchantProjection() async throws {
        let t = ContentScriptTransport(), box = SessionBox(); t.append(MerchantContentFixtureData.access)
        t.replies.append((#"{"code":500,"msg":"不存在","data":{}}"#, 200)); t.append(#"{"id":70,"name":"Recruiting before publication"}"#); t.append("[]")
        let result = try await service(t, box: box).load(.chapters(topicID: 70))
        XCTAssertEqual(result.value["topic"]["name"].text, "Recruiting before publication")
        XCTAssertEqual(t.requests[2].url?.path, "/api/topic/info-to-merchant")
    }
}

extension MerchantContentServiceTests {
    func testRecruitingUsesSingleMarketingAggregateWithoutCouponOrFunnelRequests() async throws {
        let t = MerchantContentFixtureTransport(), box = SessionBox()
        let result = try await service(t, box: box).load(.recruiting)
        XCTAssertEqual(result.rows.first?["id"].integer, 70)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/marketing-home"])
    }
    func testRecruitingRequiresFreshMarketingReadPermission() async throws {
        let t = ContentScriptTransport(), box = SessionBox()
        t.append(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}"#)
        let s = try service(t, box: box); await failure(.denied) { try await s.load(.recruiting) }
        XCTAssertEqual(t.requests.count, 1)
    }
}
