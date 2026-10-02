import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OperationFakeTransport: HTTPTransport {
    enum Reply { case json(String, Int = 200), lost }
    var replies: [Reply]; var requests: [URLRequest] = []; var onSend: ((URLRequest, Int) -> Void)?
    init(_ replies: [Reply] = []) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?(request, requests.count)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() { case .json(let json, let status): return (Data(json.utf8), status); case .lost: throw URLError(.networkConnectionLost) }
    }
}
@MainActor private final class OperationMemoryJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]; var failWrites = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + ":" + targetKey] }
    func write(_ record: OperationPendingRecord) throws {
        if failWrites { throw APIError.malformedResponse }
        if let old = try pending(ownerKey: record.ownerKey, targetKey: record.targetKey), old.operationID != record.operationID { throw APIError.invalidRequest }
        records[record.ownerKey + ":" + record.targetKey] = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        guard try pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { throw APIError.invalidRequest }
        records[record.ownerKey + ":" + record.targetKey] = nil
    }
}
private let capabilityJSON = #"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":2}}}"#
private let editJSON = #"{"code":200,"data":{"editScope":"WHITELIST","topic":{"id":71,"productType":1,"name":"Route","description":"Original","imgUrl":"fixture://cover","categoryIds":"7","updateTime":"r1"},"chapters":[],"tickets":[]}}"#
private let clubJSON = #"{"id":81,"name":"Club","city":"City","isOwner":true,"viewerIsAdmin":false,"isJoined":true,"clubType":"兴趣社群","activityPrefs":"轻社交","joinPolicySupported":true,"prioritySignupEnabled":1,"memberReservedQuota":4,"publicVisible":1,"memberPostAllowed":0,"merchantUndertakeOpen":1}"#
private let membersJSON = #"{"code":200,"data":[{"memberId":701,"isOwner":true,"role":1},{"memberId":704,"isOwner":false,"role":0}]}"#
private let accessJSON = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write","merchant:coop:manage","merchant:project:manage"]}}"#
@MainActor final class OperationHTTPAdapterTests: XCTestCase {
    private func config() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com")!) }
    private func grant(_ paths: Set<String>, namespace: String = "test-cn", account: Int = 701) throws -> OperationEndpointApproval { try .init(baseURL: config().baseURL, namespace: namespace, accountID: account, paths: paths) }
    private func body(_ r: URLRequest) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [String: Any]) }
    private func projectSession() throws -> ProjectEditSession { try .init(accountID: 701, epoch: 1, storageNamespace: "test-cn") }
    private func projectOperation(_ s: ProjectEditSession, baseline: ProjectEditSnapshot? = nil) throws -> ProjectEditPending {
        let identity: ProjectEditDraftIdentity
        if let id = baseline?.topicID { identity = try .init(topicID: id) } else { identity = try .init() }
        return try .init(operationID: UUID(), ownerKey: s.ownerKey, identity: identity,
            payload: ProjectEditContract.payload(baseline?.draft ?? ProjectEditSyntheticFixtures.draft(), topicID: baseline?.topicID, scope: baseline?.scope ?? .full), baseline: baseline)
    }
    func testProjectDefaultMakesZeroRequests() async throws {
        let s = try projectSession(), c = try ProjectEditCredentials(session: s, token: "token"), t = OperationFakeTransport()
        let service = try ProjectEditHTTPService(configuration: config(), transport: t, owner: .personal, currentCredentials: { c })
        let result = await service.submit(try projectOperation(s), session: s)
        XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
    }
    func testProjectCreateExactJSONAndDurableDispatchMarker() async throws {
        let s = try projectSession(), c = try ProjectEditCredentials(session: s, token: "token"), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), op = try projectOperation(s)
        try store.savePending(op, session: s)
        let t = OperationFakeTransport([.json(capabilityJSON), .json(#"{"code":200,"data":{"topicId":711,"auditTaskId":91,"reviewState":"PENDING","published":true,"bundledTemplateIds":[41]}}"#)])
        t.onSend = { r, _ in if r.url?.path == "/api/topic/v2/create" { XCTAssertEqual(try? store.pending(session: s, identity: op.identity)?.dispatchStarted, true) } }
        let service = try ProjectEditHTTPService(configuration: config(), transport: t, owner: .personal, approval: grant(["api/topic/v2/create"]), store: store, currentCredentials: { c })
        let result = await service.submit(op, session: s)
        XCTAssertEqual(result, .acknowledged(operationID: op.operationID, topicID: 711))
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/publish/home", "/api/topic/v2/create"])
        let r = try XCTUnwrap(t.requests.last); XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "token"); XCTAssertNil(r.value(forHTTPHeaderField: "Idempotency-Key")); XCTAssertNil(try body(r)["id"])
    }
    func testProjectMerchantDetailMultipartAndUpdateAcknowledgment() async throws {
        let s = try projectSession(), c = try ProjectEditCredentials(session: s, token: "token"), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let baseline = try ProjectEditContract.decodeEditDetail(Data(editJSON.utf8), expectedTopicID: 71, owner: .merchant), op = try projectOperation(s, baseline: baseline)
        try store.savePending(op, session: s)
        let t = OperationFakeTransport([.json(editJSON), .json(#"{"code":200,"data":{"topicId":71,"auditTaskId":null,"reviewState":"NOT_REQUIRED","published":true,"bundledTemplateIds":[]}}"#)])
        let service = try ProjectEditHTTPService(configuration: config(), transport: t, owner: .merchant, approval: grant(["api/topic/v2/update"]), store: store, currentCredentials: { c })
        let result = await service.submit(op, session: s); XCTAssertEqual(result, .acknowledged(operationID: op.operationID, topicID: 71))
        XCTAssertTrue(t.requests[0].value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        let text = String(data: t.requests[0].httpBody!, encoding: .utf8)!; XCTAssertTrue(text.contains("name=\"scope\"\r\n\r\nMERCHANT")); XCTAssertTrue(text.contains("name=\"id\"\r\n\r\n71"))
        XCTAssertEqual(t.requests[1].url?.path, "/api/topic/v2/update"); XCTAssertEqual(try body(t.requests[1])["id"] as? Int, 71)
        let receipt = try await service.terminalReceipt(operationID: op.operationID, session: s); XCTAssertNil(receipt); XCTAssertEqual(t.requests.count, 2)
    }
    func testProjectQuotaAndRevisionConflictsPreventWrites() async throws {
        let s = try projectSession(), c = try ProjectEditCredentials(session: s, token: "token")
        let baseline = try ProjectEditContract.decodeEditDetail(Data(editJSON.utf8), expectedTopicID: 71, owner: .personal)
        for existing in [false, true] {
            let op = try projectOperation(s, baseline: existing ? baseline : nil), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
            try store.savePending(op, session: s)
            let t = OperationFakeTransport([.json(existing ? editJSON.replacingOccurrences(of: "r1", with: "r2") : capabilityJSON.replacingOccurrences(of: "\"themesRemaining\":2", with: "\"themesRemaining\":0"))])
            let service = try ProjectEditHTTPService(configuration: config(), transport: t, owner: .personal, approval: grant(["api/topic/v2/create", "api/topic/v2/update"]), store: store, currentCredentials: { c })
            let result = await service.submit(op, session: s); XCTAssertEqual(result, .notSent); XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testProjectUnknownCannotReplayAfterServiceRecreation() async throws {
        let s = try projectSession(), c = try ProjectEditCredentials(session: s, token: "token"), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), op = try projectOperation(s)
        try store.savePending(op, session: s); let t = OperationFakeTransport([.json(capabilityJSON), .lost])
        for _ in 0..<2 {
            let service = try ProjectEditHTTPService(configuration: config(), transport: t, owner: .personal, approval: grant(["api/topic/v2/create"]), store: store, currentCredentials: { c })
            let result = await service.submit(op, session: s); XCTAssertEqual(result, .unknown)
        }
        XCTAssertEqual(t.requests.count, 2)
    }
    func testProjectMalformedCreateAndServerFailureAreUnknown() throws {
        let op = try projectOperation(projectSession())
        for json in [#"{"code":200}"#, #"{"code":200,"data":0}"#, #"{"code":200,"data":{"id":7}}"#, "bad"] { XCTAssertEqual(ProjectEditHTTPService.decodeAcknowledgment(Data(json.utf8), status: 200, operation: op), .unknown) }
        XCTAssertEqual(ProjectEditHTTPService.decodeAcknowledgment(Data(#"{"code":500}"#.utf8), status: 500, operation: op), .unknown)
        XCTAssertEqual(ProjectEditHTTPService.decodeAcknowledgment(Data(#"{"code":400}"#.utf8), status: 200, operation: op), .rejected)
    }
    func testProjectTokenChangeAfterDispatchIsUnknown() async throws {
        let s = try projectSession(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), op = try projectOperation(s)
        var c = try ProjectEditCredentials(session: s, token: "old"); try store.savePending(op, session: s)
        let t = OperationFakeTransport([.json(capabilityJSON), .json(#"{"code":200,"data":71}"#)])
        t.onSend = { r, _ in if r.url?.path == "/api/topic/v2/create" { c = try! .init(session: s, token: "new") } }
        let service = try ProjectEditHTTPService(configuration: config(), transport: t, owner: .personal, approval: grant(["api/topic/v2/create"]), store: store, currentCredentials: { c })
        let result = await service.submit(op, session: s); XCTAssertEqual(result, .unknown)
    }
    private func clubSession(_ epoch: UInt64 = 1) throws -> ClubOperationsSession { try .init(accountID: 701, epoch: epoch, token: "token", storageNamespace: "test-cn") }
    func testClubExactSettingJSONAndAcknowledgment() async throws {
        let s = try clubSession(), j = OperationMemoryJournal(), t = OperationFakeTransport([.json("{\"code\":200,\"data\":" + clubJSON + "}"), .json(membersJSON), .json(#"{"code":200,"data":{"publicVisible":0}}"#)])
        let service = try ClubOperationsSessionAccess(service: .init(configuration: config(), transport: t), currentSession: { s }, approval: grant(["api/club/open-settings/public-visible"]), journal: j)
        let result = try await service.perform(.openSetting(.publicVisible, enabled: false, previous: true), target: .club(81), expectedIdentity: s.identity)
        XCTAssertEqual(result.settingValue, false); XCTAssertTrue(j.records.isEmpty)
        let r = try XCTUnwrap(t.requests.last); XCTAssertEqual(r.url?.path, "/api/club/open-settings/public-visible"); XCTAssertEqual(try body(r)["id"] as? Int, 81); XCTAssertEqual(try body(r)["publicVisible"] as? Int, 0)
    }
    func testClubUnknownPersistsAcrossAdapterAndEpoch() async throws {
        var s = try clubSession(); let j = OperationMemoryJournal(), t = OperationFakeTransport([.json("{\"code\":200,\"data\":" + clubJSON + "}"), .json(membersJSON), .lost])
        for epoch in [UInt64(1), 2] {
            s = try clubSession(epoch)
            let service = try ClubOperationsSessionAccess(service: .init(configuration: config(), transport: t), currentSession: { s }, approval: grant(["api/club/set-member-role"]), journal: j)
            if epoch == 2 { XCTAssertTrue(service.hasPending(target: .club(81))) }
            do { _ = try await service.perform(.memberRole(memberID: 704, admin: true, previousRole: 0), target: .club(81), expectedIdentity: s.identity); XCTFail() } catch {}
        }
        XCTAssertEqual(t.requests.count, 3); XCTAssertEqual(j.records.count, 1)
    }
    func testClubDisabledMakesNoRequestsAndChangedOwnerPreventsWrite() async throws {
        let s = try clubSession(), t = OperationFakeTransport(), j = OperationMemoryJournal()
        let disabled = try ClubOperationsSessionAccess(service: .init(configuration: config(), transport: t), currentSession: { s })
        do { _ = try await disabled.perform(.openSetting(.publicVisible, enabled: false, previous: true), target: .club(81), expectedIdentity: s.identity); XCTFail() } catch {}
        XCTAssertTrue(t.requests.isEmpty)
        t.replies = [.json("{\"code\":200,\"data\":" + clubJSON.replacingOccurrences(of: "\"isOwner\":true", with: "\"isOwner\":false") + "}")]
        let enabled = try ClubOperationsSessionAccess(service: .init(configuration: config(), transport: t), currentSession: { s }, approval: grant(["api/club/open-settings/public-visible"]), journal: j)
        do { _ = try await enabled.perform(.openSetting(.publicVisible, enabled: false, previous: true), target: .club(81), expectedIdentity: s.identity); XCTFail() } catch {}
        XCTAssertEqual(t.requests.count, 1); XCTAssertTrue(j.records.isEmpty)
    }
    private func store() throws -> MerchantStorefront { try JSONDecoder().decode(MerchantStorefront.self, from: Data(MerchantOperationsFixtureData.storeJSON.utf8)) }
    private func merchantReplies(_ tail: [OperationFakeTransport.Reply]) -> [OperationFakeTransport.Reply] { [.json(accessJSON), .json("{\"code\":200,\"data\":" + MerchantOperationsFixtureData.storeJSON + "}")] + tail }
    func testMerchantStoryTwoExactWritesPreserveHiddenFields() async throws {
        let old = try store(); var edited = old; edited.profile.description = "New story"
        let t = OperationFakeTransport(merchantReplies([.json(#"{"code":200}"#), .json(#"{"code":200,"msg":"saved"}"#)])), j = OperationMemoryJournal(), service = try MerchantOperationsService(configuration: config(), transport: t)
        let result = try await service.save(.story(edited), token: "token", approval: grant(["api/merchant/decor/save", "api/merchant/update"]), namespace: "test-cn", accountID: 701, baseline: .story(old), journal: j, checkSession: {})
        XCTAssertEqual(result.acknowledgedSteps, 2); XCTAssertTrue(j.records.isEmpty)
        XCTAssertEqual(Array(t.requests.suffix(2)).map { $0.url!.path }, ["/api/merchant/decor/save", "/api/merchant/update"])
        XCTAssertEqual(Set(try body(t.requests[2]).keys), ["storyTitle"]); XCTAssertEqual(try body(t.requests[3])["preference"] as? String, old.profile.preference)
    }
    func testMerchantStoryUnknownFirstWriteStopsAndCannotReplay() async throws {
        let old = try store(), j = OperationMemoryJournal(), t = OperationFakeTransport(merchantReplies([.lost])), service = try MerchantOperationsService(configuration: config(), transport: t)
        for _ in 0..<2 {
            do { _ = try await service.save(.story(old), token: "token", approval: grant(["api/merchant/decor/save", "api/merchant/update"]), namespace: "test-cn", accountID: 701, baseline: .story(old), journal: j, checkSession: {}); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .outcomeUnknown) }
        }
        XCTAssertEqual(t.requests.count, 3); XCTAssertEqual(j.records.values.first?.acknowledgedSteps, 0)
    }
    func testMerchantSecondRejectLeavesPartialDurableLock() async throws {
        let old = try store(), j = OperationMemoryJournal(), t = OperationFakeTransport(merchantReplies([.json(#"{"code":200}"#), .json(#"{"code":400}"#)])), service = try MerchantOperationsService(configuration: config(), transport: t)
        do { _ = try await service.save(.story(old), token: "token", approval: grant(["api/merchant/decor/save", "api/merchant/update"]), namespace: "test-cn", accountID: 701, baseline: .story(old), journal: j, checkSession: {}); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .partial(acknowledgedSteps: 1)) }
        XCTAssertEqual(t.requests.count, 4); XCTAssertEqual(j.records.values.first?.acknowledgedSteps, 1)
        XCTAssertEqual(MerchantOperationsDestination.profile.pendingTarget, MerchantOperationsDestination.story.pendingTarget)
        XCTAssertEqual(MerchantOperationsDestination.gallery.pendingTarget, MerchantOperationsDestination.story.pendingTarget)
    }
    func testMerchantApprovalMustCoverBothStoryWritesBeforeReads() async throws {
        let old = try store(), t = OperationFakeTransport(), j = OperationMemoryJournal(), service = try MerchantOperationsService(configuration: config(), transport: t)
        do { _ = try await service.save(.story(old), token: "token", approval: grant(["api/merchant/decor/save"]), namespace: "test-cn", accountID: 701, baseline: .story(old), journal: j, checkSession: {}); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .liveWritesDisabled) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testMerchantPermissionAndJournalFailurePreventDispatch() async throws {
        let old = try store()
        for failJournal in [false, true] {
            let j = OperationMemoryJournal(); j.failWrites = failJournal
            let t = OperationFakeTransport(failJournal ? merchantReplies([]) : [.json(accessJSON.replacingOccurrences(of: "merchant:profile:write", with: "unrelated"))]), service = try MerchantOperationsService(configuration: config(), transport: t)
            do { _ = try await service.save(.story(old), token: "token", approval: grant(["api/merchant/decor/save", "api/merchant/update"]), namespace: "test-cn", accountID: 701, baseline: .story(old), journal: j, checkSession: {}); XCTFail() } catch {}
            XCTAssertFalse(t.requests.contains { $0.url!.path.hasSuffix("/save") || $0.url!.path.hasSuffix("/update") })
        }
    }
    func testMerchantTemplateAcknowledgmentRequiresPositiveNumericData() throws {
        for json in [#"{"code":200,"data":"71"}"#, #"{"code":200,"data":0}"#, #"{"code":200}"#] { XCTAssertThrowsError(try MerchantOperationsService.decodeAcknowledgment(Data(json.utf8), status: 200, template: true)) }
        XCTAssertEqual(try MerchantOperationsService.decodeAcknowledgment(Data(#"{"code":200,"data":71}"#.utf8), status: 200, template: true).templateID, 71)
    }
    func testTeamCreateOwnedContextAndPositiveTeamID() async throws {
        let s = try TeamSyntheticFixtures.session(), context = TeamSyntheticFixtures.creation, id = UUID(), j = TeamMemoryJournal(), action = TeamAction.create(context: context, size: 3, inviteOnly: false)
        try j.write(.init(operationID: id, ownerKey: s.ownerKey, targetKey: action.targetKey))
        let t = OperationFakeTransport([.json(#"{"code":200,"data":{"teamId":"4101"}}"#)])
        let service = try TeamHTTPService(configuration: config(), transport: t, approval: grant(["api/team/create"], namespace: s.storageNamespace, account: s.accountID), journal: j, currentSession: { s }, creationLoader: { owner, captured in XCTAssertEqual(owner, 5101); XCTAssertEqual(captured, s); return context })
        let result = await service.submit(action, operationID: id, session: s); XCTAssertEqual(result, .acknowledged(operationID: id, teamID: 4101))
        let r = try XCTUnwrap(t.requests.first), fields = try body(r); XCTAssertEqual(r.url?.path, "/api/team/create"); XCTAssertEqual(fields["ownerType"] as? Int, 2); XCTAssertEqual(fields["ownerId"] as? Int, 5101); XCTAssertEqual(fields["maxMembers"] as? Int, 3); XCTAssertNil(fields["joinMode"])
    }
    func testTeamCreateWithoutOwnedRegistrationLoaderDoesNotWrite() async throws {
        let s = try TeamSyntheticFixtures.session(), id = UUID(), j = TeamMemoryJournal(), t = OperationFakeTransport(), action = TeamAction.create(context: TeamSyntheticFixtures.creation, size: 3, inviteOnly: true)
        try j.write(.init(operationID: id, ownerKey: s.ownerKey, targetKey: action.targetKey))
        let service = try TeamHTTPService(configuration: config(), transport: t, approval: grant(["api/team/create"], namespace: s.storageNamespace, account: s.accountID), journal: j, currentSession: { s })
        let result = await service.submit(action, operationID: id, session: s); XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
    }
    func testTeamAllFourMemberActionsUseExactContracts() async throws {
        let s = try TeamSyntheticFixtures.session()
        for action in [TeamAction.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM"), .leave(teamID: 4101), .remove(teamID: 4101, memberID: 902), .disband(teamID: 4101)] {
            let id = UUID(), j = TeamMemoryJournal(); try j.write(.init(operationID: id, ownerKey: s.ownerKey, targetKey: action.targetKey))
            var detail = TeamSyntheticFixtures.detailJSON
            if case .join = action { detail = detail.replacingOccurrences(of: "\"joined\":true,\"leader\":true", with: "\"joined\":false,\"leader\":false") }
            let t = OperationFakeTransport([.json("{\"code\":200,\"data\":" + detail + "}"), .json(#"{"code":200}"#)]), contract = try TeamWriteContract(action)
            let service = try TeamHTTPService(configuration: config(), transport: t, approval: grant([String(contract.path.dropFirst())], namespace: s.storageNamespace, account: s.accountID), journal: j, currentSession: { s })
            let result = await service.submit(action, operationID: id, session: s); XCTAssertEqual(result, .acknowledged(operationID: id, teamID: 4101))
            let r = try XCTUnwrap(t.requests.last); XCTAssertEqual(r.url?.path, contract.path); XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
            if case .join = action { XCTAssertEqual(try body(r)["inviteCode"] as? String, "SYNTHETIC-TEAM"); XCTAssertNil(try body(r)["teamId"]) } else { XCTAssertEqual(try body(r)["teamId"] as? Int, 4101) }
        }
    }
    func testTeamUnknownCannotReplayAfterServiceRecreation() async throws {
        let s = try TeamSyntheticFixtures.session(), id = UUID(), j = TeamMemoryJournal(), action = TeamAction.leave(teamID: 4101)
        try j.write(.init(operationID: id, ownerKey: s.ownerKey, targetKey: action.targetKey))
        let t = OperationFakeTransport([.json("{\"code\":200,\"data\":" + TeamSyntheticFixtures.detailJSON + "}"), .lost])
        for _ in 0..<2 {
            let service = try TeamHTTPService(configuration: config(), transport: t, approval: grant(["api/team/quit"], namespace: s.storageNamespace, account: s.accountID), journal: j, currentSession: { s })
            let result = await service.submit(action, operationID: id, session: s); XCTAssertEqual(result, .unknown)
            let receipt = try await service.receipt(operationID: id, session: s); XCTAssertNil(receipt)
        }
        XCTAssertEqual(t.requests.count, 2)
    }
    func testTeamWrongNamespaceBlocksReadsAndWrites() async throws {
        let s = try TeamSyntheticFixtures.session(), t = OperationFakeTransport(), j = TeamMemoryJournal()
        let approval = try grant(["api/team/my", "api/team/quit"], namespace: "wrong-region", account: s.accountID)
        let service = try TeamHTTPService(configuration: config(), transport: t, approval: approval, journal: j, currentSession: { s })
        let result = await service.submit(.leave(teamID: 4101), operationID: UUID(), session: s); XCTAssertEqual(result, .notSent)
        let reader = try TeamReadOnlyService(configuration: config(), transport: t, readApproval: approval, currentSession: { s })
        do { _ = try await reader.myTeams(session: s); XCTFail() } catch { XCTAssertEqual(error as? TeamFailure, .notConfigured) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testDurableJournalSeparatesNamespaceAccountAndTarget() throws {
        let name = "operation-adapter-" + UUID().uuidString, defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let j = OperationDefaultsJournal(defaults: defaults), record = OperationPendingRecord(ownerKey: "cn:701", targetKey: "club:81", acknowledgedSteps: 1)
        try j.write(record); XCTAssertEqual(try OperationDefaultsJournal(defaults: defaults).pending(ownerKey: "cn:701", targetKey: "club:81"), record)
        XCTAssertNil(try j.pending(ownerKey: "us:701", targetKey: "club:81")); XCTAssertNil(try j.pending(ownerKey: "cn:702", targetKey: "club:81")); XCTAssertNil(try j.pending(ownerKey: "cn:701", targetKey: "club:82"))
        XCTAssertThrowsError(try j.write(.init(ownerKey: "cn:701", targetKey: "club:81")))
        let saved = String(data: try JSONEncoder().encode(record), encoding: .utf8)!; XCTAssertFalse(saved.contains("token")); XCTAssertFalse(saved.contains("inviteCode")); XCTAssertFalse(saved.contains("draft"))
        try j.clear(record); XCTAssertNil(try j.pending(ownerKey: "cn:701", targetKey: "club:81"))
    }
    func testTeamCoordinatorAcceptsAcknowledgmentAndClearsDispatchedJournal() async throws {
        let session = try TeamSyntheticFixtures.session(), journal = TeamMemoryJournal()
        let detail = "{\"code\":200,\"data\":" + TeamSyntheticFixtures.detailJSON + "}"
        let transport = OperationFakeTransport([.json(detail), .json(detail), .json(detail), .json(#"{"code":200}"#)])
        let service = try TeamHTTPService(configuration: config(), transport: transport, approval: grant(["api/team/quit"], namespace: session.storageNamespace, account: session.accountID), journal: journal, currentSession: { session })
        let coordinator = TeamCoordinator(service: service, journal: journal, currentSession: { session })
        await coordinator.loadDetail(.id(4101)); coordinator.prepare(.leave(teamID: 4101))
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        XCTAssertEqual(coordinator.writeState, .acknowledged); XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(coordinator.completedTeamID, 4101); XCTAssertFalse(coordinator.canSimulate)
    }
    func testProjectCoordinatorStoresAcknowledgmentWithoutClaimingSimulation() async throws {
        let session = try projectSession(), credentials = try ProjectEditCredentials(session: session, token: "token")
        let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), draft = ProjectEditSyntheticFixtures.draft()
        let transport = OperationFakeTransport([.json(capabilityJSON), .json(capabilityJSON), .json(#"{"code":200,"data":711}"#)])
        let service = try ProjectEditHTTPService(configuration: config(), transport: transport, owner: .personal, approval: grant(["api/topic/create"]), store: store, currentCredentials: { credentials })
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { session })
        await coordinator.load(); coordinator.prepare(draft); await coordinator.confirm(try XCTUnwrap(coordinator.confirmation))
        XCTAssertEqual(coordinator.state, .acknowledged); XCTAssertEqual(coordinator.pending?.serverAcknowledged, true)
        XCTAssertEqual(coordinator.pending?.completedTopicID, 711); XCTAssertFalse(coordinator.canSimulate)
    }

}
