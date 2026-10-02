import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PublishingFakeTransport: HTTPTransport {
    var replies: [String?]
    var requests: [URLRequest] = []
    var onSend: ((URLRequest) -> Void)?
    init(_ replies: [String?]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?(request)
        guard !replies.isEmpty, let value = replies.removeFirst() else { throw URLError(.networkConnectionLost) }
        return (Data(value.utf8), 200)
    }
}
@MainActor private final class PublishingTestJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var failWrite = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { if failWrite { throw PublishModesError.storage }; records[record.ownerKey + record.targetKey] = record }
    func clear(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = nil }
}
@MainActor private final class PublishingTestStorage: ProjectEditDataStorage {
    var data: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { data[key] }
    func write(_ value: Data, key: String) throws { data[key] = value }
    func remove(_ key: String) throws { data[key] = nil }
}
private let publishingClub = #"{"code":200,"data":{"role":"club"}}"#
private let publishingPlayer = #"{"code":200,"data":{"role":"player"}}"#
@MainActor final class PublishingModesTests: XCTestCase {
    private func session(role: String = "club", account: Int = 901, region: PublishingRegion = .china) -> PublishingSession { .init(namespace: "synthetic-cn", accountID: account, epoch: UUID(), role: role, region: region) }
    private func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.invalid")!) }
    private func draft() -> ActivityPublishDraft {
        var d = ActivityPublishDraft(); d.name = "Synthetic activity"; d.description = "Synthetic description"; d.coverURL = "fixture://cover"; d.addressName = "Synthetic place"
        d.start = "2030-05-01 10:00:00"; d.end = "2030-05-01 12:00:00"; d.playTemplateID = .init(rawValue: 8); d.categoryIDs = [2, 3]
        var t = ActivityPublishTicket(); t.name = "Synthetic ticket"; t.price = "0"; t.stock = "2"; t.start = d.start; t.end = d.end; d.tickets = [t]; return d
    }
    private func service(_ transport: PublishingFakeTransport, session: PublishingSession, journal: PublishingTestJournal? = nil, approved: Bool = true) throws -> PublishingService {
        let c = try PublishingCredentials(session: session, token: "synthetic-token")
        let a = try OperationEndpointApproval(baseURL: configuration().baseURL, namespace: session.namespace, accountID: session.accountID, paths: ["api/activity/publish", "api/topic/delete", "api/topic/update_user_status"])
        return try PublishingService(configuration: configuration(), transport: transport, approval: approved ? a : nil, journal: journal, credentials: { c })
    }
    func testActivityExactPayloadAndEmptyCollaborators() throws {
        let body = try draft().wire()
        XCTAssertEqual(body["categoryIds"], .string("2,3")); XCTAssertEqual(body["collaborators"], .array([])); XCTAssertNil(body["collaboratorIds"])
        XCTAssertEqual(body["imgUrl"], body["imgArr"]); XCTAssertEqual(body["templateId"], .number(8)); XCTAssertNil(body["id"])
        XCTAssertEqual(body["tickets"]?.array?.first?.object?["price"], .number(0))
        XCTAssertEqual(body["tickets"]?.array?.first?.object?["totalStock"], .number(2))
    }
    func testActivityMissingPriceIsNotFree() { var d = draft(); d.tickets[0].price = ""; XCTAssertThrowsError(try d.wire()); d.tickets[0].price = "0"; XCTAssertNoThrow(try d.wire()) }
    func testActivityDateAndTicketWindowValidation() {
        var d = draft(); d.end = d.start; XCTAssertThrowsError(try d.wire())
        d = draft(); d.tickets[0].start = "2030-05-01 09:59:59"; XCTAssertThrowsError(try d.wire())
        d = draft(); d.tickets[0].end = "2030-05-01 12:00:01"; XCTAssertThrowsError(try d.wire())
        d = draft(); d.tickets[0].stock = "0"; XCTAssertThrowsError(try d.wire())
        d = draft(); d.start = "2030-02-30 10:00:00"; XCTAssertThrowsError(try d.wire())
    }
    func testDefaultCapabilityAndNullQuota() {
        let capability = PublishingCapability([:]); XCTAssertEqual(capability.role, "player"); XCTAssertFalse(capability.activity); XCTAssertTrue(capability.simple); XCTAssertFalse(capability.quotaExhausted)
        XCTAssertTrue(PublishingCapability(["quota": .object(["themesRemaining": .number(0)])]).quotaExhausted)
    }
    func testQuickAIRejectsWholeOversizedOrPartialDraft() throws {
        let row = ProjectEditJSON.object(["task": .string("Walk"), "longitude": .string("1"), "latitude": .string("1")])
        let d = try QuickPublishDraft.parseAI(["draft": .object(["title": .string("Title"), "nodes": .array([row])])]); XCTAssertNil(d.nodes[0].confirmedPlace); XCTAssertThrowsError(try d.professionalSeed())
        XCTAssertThrowsError(try QuickPublishDraft.parseAI(["draft": .object(["title": .string("Title"), "nodes": .array(Array(repeating: row, count: 4))])]))
        XCTAssertThrowsError(try QuickPublishDraft.parseAI(["draft": .object(["title": .string("Title"), "nodes": .array([row, .object([:])])])]))
    }
    func testQuickSeedKeepsProductAndProfessionalIdentity() throws {
        var d = QuickPublishDraft(); d.title = " Route "; d.product = .freeExplore
        var n = QuickPublishNode(); n.name = "Place"; n.confirmedPlace = try .init(id: "local", name: "Place", address: "Street", latitude: 31, longitude: 121); d.nodes = [n]
        let seed = try d.professionalSeed(); XCTAssertEqual(seed.product, .freeExplore); XCTAssertEqual(seed.preserved["publishMode"], .string("ai_simple")); XCTAssertEqual(seed.chapters[0].nodes[0].address, "Street"); XCTAssertEqual(seed.tickets[0].price, "0")
    }
    func testTopicRewardEmptyAndZeroRules() throws {
        var r = PublishingTopicRewards(); r.selfPlay = true; r.couponID = 7
        let d = try r.applying(to: .init()); XCTAssertEqual(d.preserved["selfPlay"], .number(1)); XCTAssertEqual(d.preserved["selfPlayPrice"], .number(0)); XCTAssertEqual(d.preserved["completeRewardCouponId"], .number(7)); XCTAssertNil(d.preserved["finishMedalImg"])
        r.selfPlayPrice = "-1"; XCTAssertThrowsError(try r.applying(to: .init()))
    }
    private func project(kind: String = "topic", state: String = "offline", signups: Int = 0, owner: String = "member") throws -> PublishingProject {
        try .init(["id": .number(17), "bizType": .string(kind), "title": .string("Fixture"), "state": .string(state), "signupCount": .number(Decimal(signups)), "ownerType": .string(owner)])
    }
    func testBusinessSpecificPathsAndExpectedTopicStatus() throws {
        let paths = ["topic": "api/topic/update_user_status", "activity": "api/activity/update_publish_status", "template": "api/template/updateLibraryStatus"]
        for (kind, path) in paths { let req = try PublishingContracts.project(project(kind: kind), action: .toggle); XCTAssertEqual(req.path, path); XCTAssertEqual(req.fields["id"], .string("17")); XCTAssertEqual(req.fields["expectedUserStatus"], kind == "topic" ? .string("0") : nil) }
        XCTAssertThrowsError(try project(kind: "unknown")); XCTAssertThrowsError(try PublishedResource(kind: .activity, value: 0))
    }
    func testDeletionAndFinancialRules() throws {
        XCTAssertFalse(try project(signups: 1).canDelete); XCTAssertFalse(try project(state: "running").canDelete)
        XCTAssertFalse(try project(owner: "club").canCancelWithRefund)
        XCTAssertFalse(try project(kind: "activity", signups: 1, owner: "merchant").canCancelWithRefund)
        XCTAssertTrue(try project(kind: "activity", signups: 1).canCancelWithRefund)
    }
    func testReadContractsKeepSourceFieldNamesAndPageOne() {
        XCTAssertEqual(PublishingRead.categories(activity: true).request.fields, ["parentid": .string("0"), "type": .string("2")])
        XCTAssertEqual(PublishingRead.collaborators(keyword: "  q ").request.fields, ["user_type": .string("0"), "keyword": .string("q")])
        XCTAssertEqual(PublishingRead.templates(keyword: "", scope: "MERCHANT").request.fields, ["is_quote": .string("1"), "scope": .string("MERCHANT")])
        XCTAssertEqual(PublishingRead.projects(type: "all", state: "all", ownerType: "all", scope: "", pageSize: 200).request.fields["pageNum"], .string("1"))
    }
    func testCategoriesUseCategoryName() throws { XCTAssertEqual(try PublishingContracts.options(.array([.object(["id": .number(2), "categoryName": .string("Source category")])]), kind: .categories(activity: true)).first?.name, "Source category") }
    func testUnknownRowsPreservedAndTruncationExplicit() throws {
        let p = try PublishingContracts.decodeProjects(.object(["rows": .array([.object(["id": .number(1), "bizType": .string("future")])]), "total": .string("7")]))
        XCTAssertTrue(p.rows.isEmpty); XCTAssertEqual(p.unknownRows.count, 1); XCTAssertTrue(p.truncated)
    }
    func testIdentityNoUSOrAlreadyRegisteredMutation() {
        XCTAssertThrowsError(try PublishingIdentity.registration(name: "Synthetic", idCard: "", consent: true, source: "topic_publish", region: .unitedStates, registered: false, currentYear: 2030))
        XCTAssertThrowsError(try PublishingIdentity.registration(name: "Synthetic", idCard: "", consent: true, source: "topic_publish", region: .china, registered: true, currentYear: 2030))
        XCTAssertFalse(PublishingIdentity.validChinaID("000000203002300000", currentYear: 2030)); XCTAssertEqual(PublishingIdentity.normalize(" a x \n"), "AX")
    }
    func testDisabledMutationDoesNotSend() async throws {
        let s = session(), t = PublishingFakeTransport([publishingClub]), api = try service(t, session: s, approved: false)
        let review = try await api.prepareActivity(draft(), session: s); let outcome = await api.submit(review)
        XCTAssertEqual(outcome, .notSent); XCTAssertEqual(t.requests.count, 1)
    }
    func testActivityExactHTTPAndJournalBeforeDispatch() async throws {
        let s = session(), journal = PublishingTestJournal(), t = PublishingFakeTransport([publishingClub, publishingClub, #"{"code":200}"#]), api = try service(t, session: s, journal: journal)
        t.onSend = { request in if request.url?.path == "/api/activity/publish" { XCTAssertEqual(journal.records.count, 1); XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key")) } }
        let review = try await api.prepareActivity(draft(), session: s); let outcome = await api.submit(review)
        XCTAssertEqual(outcome, .acknowledged); XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/publish/home", "/api/publish/home", "/api/activity/publish"])
        let replay = await api.submit(review); XCTAssertEqual(replay, .notSent); XCTAssertEqual(t.requests.count, 3)
    }
    func testLostResponseBlocksNewReviewsAndRestart() async throws {
        let s = session(), journal = PublishingTestJournal(), t = PublishingFakeTransport([publishingClub, publishingClub, nil]), api = try service(t, session: s, journal: journal)
        let review = try await api.prepareActivity(draft(), session: s); let lost = await api.submit(review); XCTAssertEqual(lost, .unknown)
        let freshTransport = PublishingFakeTransport([publishingClub]), restarted = try service(freshTransport, session: s, journal: journal)
        let fresh = try await restarted.prepareActivity(draft(), session: s); let retry = await restarted.submit(fresh)
        XCTAssertEqual(retry, .unknown); XCTAssertEqual(freshTransport.requests.count, 1)
    }
    func testRoleRevocationStopsBeforeWrite() async throws {
        let s = session(), t = PublishingFakeTransport([publishingClub, publishingPlayer]), api = try service(t, session: s, journal: PublishingTestJournal())
        let review = try await api.prepareActivity(draft(), session: s); let outcome = await api.submit(review)
        XCTAssertEqual(outcome, .notSent); XCTAssertEqual(t.requests.count, 2)
    }
    func testCancelledReviewCannotDispatch() async throws {
        let s = session(), t = PublishingFakeTransport([publishingClub]), api = try service(t, session: s, journal: PublishingTestJournal())
        let review = try await api.prepareActivity(draft(), session: s); api.cancel(review); let outcome = await api.submit(review); XCTAssertEqual(outcome, .notSent)
    }
    func testStorageFailureMakesZeroMutationRequests() async throws {
        let s = session(), j = PublishingTestJournal(); j.failWrite = true
        let t = PublishingFakeTransport([publishingClub, publishingClub]), api = try service(t, session: s, journal: j)
        let review = try await api.prepareActivity(draft(), session: s); let outcome = await api.submit(review); XCTAssertEqual(outcome, .notSent); XCTAssertFalse(t.requests.contains { $0.url?.path == "/api/activity/publish" })
    }
    func testAccountEpochChangeRejectsRead() async throws {
        let s = session(); var c: PublishingCredentials? = try .init(session: s, token: "synthetic")
        let t = PublishingFakeTransport([publishingClub]); t.onSend = { _ in c = nil }
        let api = try PublishingService(configuration: configuration(), transport: t, credentials: { c })
        do { _ = try await api.read(.capability, session: s); XCTFail("Stale account result accepted") } catch { XCTAssertEqual(error as? PublishModesError, .changedSession) }
    }
    func testIdentityFailureClosedAndUSZeroRequests() async throws {
        let s = session(region: .unitedStates), t = PublishingFakeTransport([]), api = try service(t, session: s)
        do { _ = try await api.identityRegistered(session: s); XCTFail("Unsupported region is not an authoritative false") } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testSecureDraftOwnerAndBaselineIsolation() throws {
        let store = PublishingDraftStore(storage: PublishingTestStorage()), s = session(), id = UUID()
        let envelope = try PublishingLocalDraft(session: s, identity: id, baseline: "v1", activity: draft()); try store.save(envelope, session: s)
        XCTAssertThrowsError(try store.load(id: id, baseline: "v2", session: s)); XCTAssertEqual(try store.load(id: id, baseline: "v1", session: s), envelope)
        XCTAssertNil(try store.load(id: id, baseline: "v1", session: session(account: 902)))
    }
    func testProjectBaselineConflictPreventsToggle() async throws {
        let s = session(), p = try project()
        let envelope = "{\"code\":200,\"data\":{\"rows\":[" + String(data: try JSONEncoder().encode(p.raw), encoding: .utf8)! + "],\"total\":1}}"
        let changed = envelope.replacingOccurrences(of: "offline", with: "running")
        let t = PublishingFakeTransport([envelope, changed]), api = try service(t, session: s, journal: PublishingTestJournal())
        let query = PublishingRead.projects(type: "all", state: "all", ownerType: "all", scope: "", pageSize: 200)
        let review = try await api.prepareProject(p, action: .toggle, query: query, session: s)
        let outcome = await api.submit(review); XCTAssertEqual(outcome, .notSent)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/project/my", "/api/project/my"])
    }
    func testProjectToggleUsesMultipartAndReviewedExpectedStatus() async throws {
        let s = session(), p = try project()
        let envelope = "{\"code\":200,\"data\":{\"rows\":[" + String(data: try JSONEncoder().encode(p.raw), encoding: .utf8)! + "],\"total\":1}}"
        let t = PublishingFakeTransport([envelope, envelope, #"{"code":200}"#]), api = try service(t, session: s, journal: PublishingTestJournal())
        let query = PublishingRead.projects(type: "all", state: "all", ownerType: "all", scope: "", pageSize: 200)
        let review = try await api.prepareProject(p, action: .toggle, query: query, session: s)
        let outcome = await api.submit(review); XCTAssertEqual(outcome, .acknowledged)
        let request = try XCTUnwrap(t.requests.last), body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        XCTAssertTrue(body.contains("name=\"expectedUserStatus\"\r\n\r\n0")); XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n17"))
    }

    func testRewardBindingRetainsIntermediateInputUntilReview() throws {
        var rewards = PublishingTopicRewards(); rewards.selfPlay = true; rewards.selfPlayPrice = "1."
        let draft = rewards.updatingDraft(.init())
        XCTAssertEqual(PublishingTopicRewards(draft: draft).selfPlayPrice, "1.")
        XCTAssertThrowsError(try PublishingTopicRewards(draft: draft).applying(to: draft))
        rewards.selfPlayPrice = "1.25"; XCTAssertNoThrow(try rewards.applying(to: draft))
    }
    func testSecureActiveDraftSeparatesModesAndAccounts() throws {
        let s = session(), store = PublishingDraftStore(storage: PublishingTestStorage())
        let activity = try PublishingLocalDraft(session: s, identity: UUID(), activity: draft())
        var quick = QuickPublishDraft(); quick.title = "Synthetic quick draft"
        let quickEnvelope = try PublishingLocalDraft(session: s, identity: UUID(), quick: quick)
        try store.saveActive(activity, session: s); try store.saveActive(quickEnvelope, session: s)
        XCTAssertEqual(try store.loadActive(activity: true, session: s), activity)
        XCTAssertEqual(try store.loadActive(activity: false, session: s), quickEnvelope)
        XCTAssertNil(try store.loadActive(activity: true, session: session(account: 902)))
    }
    func testReadApprovalNeverAllowsIdentityMutationPath() async throws {
        let s = session(), t = PublishingFakeTransport([]), c = try configuration()
        let grant = try OperationEndpointApproval(baseURL: c.baseURL, namespace: s.namespace, accountID: s.accountID, paths: ["api/publisher/identity"])
        let reader = PublishingApprovedReadTransport(configuration: c, approval: grant, transport: t, currentCredentials: { try? PublishingCredentials(session: s, token: "synthetic-token") })
        var request = URLRequest(url: c.baseURL.appendingPathComponent("api/publisher/identity")); request.httpMethod = "POST"; request.setValue("synthetic-token", forHTTPHeaderField: "Authorization")
        do { _ = try await reader.send(request, credential: try PublishingCredentials(session: s, token: "synthetic-token")); XCTFail("Mutation escaped read wrapper") } catch { XCTAssertEqual(error as? PublishModesError, .unavailable) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testReadApprovalMatchesAccountHostAndExactPath() async throws {
        let s = session(), t = PublishingFakeTransport([publishingClub]), c = try configuration()
        let grant = try OperationEndpointApproval(baseURL: c.baseURL, namespace: s.namespace, accountID: s.accountID, paths: ["api/publish/home"])
        let reader = PublishingApprovedReadTransport(configuration: c, approval: grant, transport: t, currentCredentials: { try? PublishingCredentials(session: s, token: "synthetic-token") })
        var request = URLRequest(url: c.baseURL.appendingPathComponent("api/publish/home")); request.httpMethod = "POST"; request.setValue("synthetic-token", forHTTPHeaderField: "Authorization")
        _ = try await reader.send(request, credential: try PublishingCredentials(session: s, token: "synthetic-token")); XCTAssertEqual(t.requests.count, 1)
        request.url = URL(string: "https://other.invalid/api/publish/home")
        do { _ = try await reader.send(request, credential: try PublishingCredentials(session: s, token: "synthetic-token")); XCTFail("Unapproved host") } catch { XCTAssertEqual(error as? PublishModesError, .unavailable) }
        XCTAssertEqual(t.requests.count, 1)
    }

    func testApprovedReadRejectsStaleCredentialBeforeDispatch() async throws {
        let old = session(), c = try configuration()
        let captured = try PublishingCredentials(session: old, token: "old-token")
        let variants = [
            session(account: old.accountID + 1),
            session(account: old.accountID), // Same account, new epoch.
            PublishingSession(namespace: "other", accountID: old.accountID, epoch: old.epoch, role: old.role, region: old.region),
            old // Credential rotation even if caller's epoch has not changed.
        ]
        for (index, current) in variants.enumerated() {
            let live = try PublishingCredentials(session: current, token: index == variants.count - 1 ? "new-token" : "old-token")
            let fake = PublishingFakeTransport([publishingClub])
            let grant = try OperationEndpointApproval(baseURL: c.baseURL, namespace: current.namespace, accountID: current.accountID, paths: ["api/publish/home"])
            let guarded = PublishingApprovedReadTransport(configuration: c, approval: grant, transport: fake, currentCredentials: { live })
            let request = try AuthRequestBuilder.makeFormRequest(url: c.baseURL.appendingPathComponent("api/publish/home"), fields: [:], token: captured.token)
            do { _ = try await guarded.send(request, credential: captured); XCTFail("Stale request dispatched") }
            catch { XCTAssertEqual(error as? PublishModesError, .changedSession) }
            XCTAssertTrue(fake.requests.isEmpty)
        }
    }
    func testPublishingBoundReadSuccessAndUnboundOrForgedHeaderDenied() async throws {
        let s = session(), c = try configuration(), credential = try PublishingCredentials(session: s, token: "synthetic-token")
        let fake = PublishingFakeTransport([publishingClub])
        let grant = try OperationEndpointApproval(baseURL: c.baseURL, namespace: s.namespace, accountID: s.accountID, paths: ["api/publish/home"])
        let guarded = PublishingApprovedReadTransport(configuration: c, approval: grant, transport: fake, currentCredentials: { credential })
        let api = PublishingService(configuration: c, transport: guarded, credentials: { credential })
        _ = try await api.read(.capability, session: s)
        XCTAssertEqual(fake.requests.count, 1)
        let forged = try AuthRequestBuilder.makeFormRequest(url: c.baseURL.appendingPathComponent("api/publish/home"), fields: [:], token: "different-token")
        do { _ = try await guarded.send(forged, credential: credential); XCTFail() } catch {}
        do { _ = try await guarded.send(forged); XCTFail() } catch {}
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testIdentityStatusRequiresAuthoritativeBoolean() async throws {
        let s = session()
        for invalid in [nil, #"{"code":500,"data":{"registered":false}}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"registered":"false"}}"#] as [String?] {
            let api = try service(PublishingFakeTransport([invalid]), session: s)
            do { _ = try await api.identityRegistered(session: s); XCTFail("Unknown status became authoritative") } catch {}
        }
        for expected in [false, true] {
            let fake = PublishingFakeTransport(["{\"code\":200,\"data\":{\"registered\":\(expected)}}"])
            let api = try service(fake, session: s)
            let result = try await api.identityRegistered(session: s)
            XCTAssertEqual(result, expected)
        }
    }

    func testPublishingApprovedReadRejectsEpochChangeDuringResponse() async throws {
        let s = session(), c = try configuration(), captured = try PublishingCredentials(session: s, token: "fake")
        var live: PublishingCredentials? = captured
        let fake = PublishingFakeTransport([publishingClub]); fake.onSend = { _ in live = nil }
        let grant = try OperationEndpointApproval(baseURL: c.baseURL, namespace: s.namespace, accountID: s.accountID, paths: ["api/publish/home"])
        let guarded = PublishingApprovedReadTransport(configuration: c, approval: grant, transport: fake, currentCredentials: { live })
        let request = try AuthRequestBuilder.makeFormRequest(url: c.baseURL.appendingPathComponent("api/publish/home"), fields: [:], token: "fake")
        do { _ = try await guarded.send(request, credential: captured); XCTFail() }
        catch { XCTAssertEqual(error as? PublishModesError, .changedSession) }
        XCTAssertEqual(fake.requests.count, 1)
    }

}
