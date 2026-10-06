import XCTest
@testable import Questify

@MainActor final class ProjectEditCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.com/native")!
    private final class Grant {
        var enabled = true, write = true, read = true, review = false, legacyOnly = false
        var generation: UInt64 = 1
    }
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], role = "player", product = ProjectEditProduct.city
        var holdHome = false, failWrite = false
        var started: XCTestExpectation?, held: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-project-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/publish/home") {
                if holdHome { return try await withCheckedThrowingContinuation { held = $0; started?.fulfill() } }
                return (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":3}}}"#.utf8), 200)
            }
            if path.hasSuffix("/topic/edit-detail") { return (try ProjectEditRemoteFixtures.detail(product: product), 200) }
            if path.hasSuffix("/review/prepare") { return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": ApprovedTopicReviewSynthetic.captureFields()]), 200) }
            if path.hasSuffix("/review/submit") || path.hasSuffix("/review/status") {
                let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
                return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": ApprovedTopicReviewSynthetic.receiptFields(command: body)]), 200)
            }
            if path.hasSuffix("/topic/v2/create") || path.hasSuffix("/topic/v2/update") {
                if failWrite { throw URLError(.timedOut) }
                return (Data(#"{"code":200,"data":{"topicId":7901,"auditTaskId":3301,"reviewState":"PENDING","published":true,"bundledTemplateIds":[41]}}"#.utf8), 200)
            }
            if path.hasSuffix("/topic/create") || path.hasSuffix("/topic/update") { return (Data(#"{"code":200,"data":7901}"#.utf8), 200) }
            throw APIError.invalidRequest
        }
        func finishHome() { let prior = held; held = nil; prior?.resume(returning: (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":3}}}"#.utf8),200)) }
        func finish401() { let prior = held; held = nil; prior?.resume(returning: (Data(),401)) }
    }
    private func configuration(_ context: RuntimeDependencyContext, _ grant: Grant) -> BusinessRuntimeConfiguration? {
        guard grant.enabled else { return nil }
        var routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]
        if grant.read { routes[.projectRead] = try? Set([.post("api/publish/home"), .post("api/topic/edit-detail")]) }
        if grant.write { routes[.projectWrite] = try? Set([.post("api/topic/create"), .post("api/topic/update"), .post(ProjectEditStoryContract.createPath), .post(ProjectEditStoryContract.updatePath)]) }
        if grant.legacyOnly { routes = [.publishingRead: try! [.post("api/publish/home")], .publishingWrite: try! [.post("api/topic/create")]] }
        if grant.review {
            routes[.approvedTopicReviewPrepare] = try? [.post(ApprovedTopicReviewPath.prepare)]
            routes[.approvedTopicReviewSubmit] = try? [.post(ApprovedTopicReviewPath.submit)]
            routes[.approvedTopicReviewStatus] = try? [.post(ApprovedTopicReviewPath.status)]
        }
        return try? .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, routes: routes)
    }
    private func root(_ wire: Wire, _ grant: Grant, _ vault: Vault = Vault()) throws -> AppCompositionRoot {
        let suite = "project-composition-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.project."+UUID().uuidString.lowercased(), realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }, sessionDependencies: { context in .init(businessConfiguration: self.configuration(context, grant)) })
    }
    private func login(_ session: AppSession) async { session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000",code: "123456"); XCTAssertEqual(session.account?.id,7) }
    private func json(_ path: String, _ fields: [String: ProjectEditJSON]) throws -> URLRequest {
        try OperationAdapterHTTP.json(configuration: .init(baseURL: base), path: path, body: JSONEncoder().encode(fields), token: "synthetic-project-7")
    }
    private func fence(_ wire: Wire, _ grant: Grant) throws -> CompositionHTTPTransport {
        let transport = try root(wire,grant).transport()
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-project-7", viewerRevision: 1) }
        transport.projectEditConfiguration = { self.configuration($0,grant) }; transport.projectEditConfigurationRevision = { grant.generation }; return transport
    }
    private func draft(_ product: ProjectEditProduct = .city) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(product: product)
        if product == .city { value.preserved["publishMode"] = .string("pro") }
        return value
    }
    func testOrdinaryFactoryCreatorSubmitThenReviewRequestUsesOriginalAcknowledgment() async throws {
        let wire = Wire(), grant = Grant(); grant.review = true
        let session = try root(wire,grant).makeSession(); await login(session); wire.requests = []
        let editor = session.projectEditor(product: .city); await editor.load(); XCTAssertTrue(editor.canSubmit)
        editor.prepare(draft()); let original = try XCTUnwrap(editor.confirmation); await editor.confirm(original)
        XCTAssertEqual(editor.state,.acknowledged); let pending = try XCTUnwrap(editor.pending), owner = try XCTUnwrap(editor.session)
        XCTAssertEqual(pending.bundleAcknowledgment?.auditTaskID,3301); XCTAssertEqual(pending.bundleAcknowledgment?.reviewState,"PENDING")
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("/topic/v2/create") }.count,1)
        let origin = try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending,session: owner)), source = try XCTUnwrap(editor.releaseReviewSource), journal = try XCTUnwrap(editor.releaseReviewJournal)
        let flow = ApprovedTopicReviewFlow(origin:origin,session:owner,source:source,journal:journal,stillCurrent:{true})
        await flow.load(); guard case .ready(let capture) = flow.state else { return XCTFail("Real composition capture unavailable") }
        let review = try XCTUnwrap(flow.review(capture)), claim = try XCTUnwrap(flow.claim(review)); await flow.submit(claim)
        guard case .known(let receipt) = flow.state else { return XCTFail("Expected submission only") }
        XCTAssertEqual(receipt.auditTaskID,4402); XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(editor.pending),pending))
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("/review/submit") }.count,1)
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("/publish") || $0.url!.path.hasSuffix("/start") })
        await editor.confirm(original); XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("/topic/v2/create") }.count,1)
    }
    func testReadOnlyAndDefaultFactoriesNeverSendCreatorWrite() async throws {
        for enabled in [false,true] {
            let wire = Wire(), grant = Grant(); grant.enabled = enabled; grant.write = false
            let session = try root(wire,grant).makeSession(); await login(session); wire.requests = []
            let editor = session.projectEditor(product:.city); await editor.load(); editor.prepare(draft()); let review = try XCTUnwrap(editor.confirmation)
            XCTAssertFalse(editor.canSubmit); await editor.confirm(review); XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testPersonalAndMerchantDetailDecodeBothServerModesWithoutBorrowingPublishingGrant() async throws {
        let wire = Wire(), grant = Grant(), transport = try fence(wire,grant), owner = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"native",viewerRevision:1)
        for scope in [ProjectEditOwner.personal,.merchant] { for product in ProjectEditProduct.allCases {
            wire.product = product
            let service = ProjectEditHTTPService(configuration:try .init(baseURL:base),transport:transport,owner:scope,currentCredentials:{try? .init(session:owner,token:"synthetic-project-7")})
            let result = try await service.preflight(topicID:71,session:owner)
            XCTAssertEqual(result.snapshot?.draft.product,product); XCTAssertEqual(result.snapshot?.draft.owner,scope)
            XCTAssertEqual(Array(try XCTUnwrap(result.snapshot?.draft.chapters[0].nodes[0].description).utf8),Array("  Raw e\u{301}\n".utf8))
        } }
        XCTAssertEqual(wire.requests.count,4); grant.legacyOnly = true
        do { _ = try await transport.send(json("api/publish/home",[:])); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,4)
    }
    func testBothCreateModesAndWhitelistUpdateSelectOnlyExistingExactPaths() throws {
        for product in ProjectEditProduct.allCases {
            let body = try ProjectEditContract.payload(draft(product),topicID:nil,scope:.full)
            let expected = product == .city ? ProjectEditStoryContract.createPath : "api/topic/create"
            XCTAssertEqual(ProjectEditCompositionRoute(request:try json(expected,body),baseURL:base)?.path,expected)
            let other = product == .city ? "api/topic/create" : ProjectEditStoryContract.createPath
            XCTAssertNil(ProjectEditCompositionRoute(request:try json(other,body),baseURL:base))
        }
        let minimal:[String:ProjectEditJSON] = ["id":.number(71),"scope":.string(""),"name":.string("Copy only")]
        for path in ["api/topic/update",ProjectEditStoryContract.updatePath] { XCTAssertEqual(ProjectEditCompositionRoute(request:try json(path,minimal),baseURL:base)?.path,path) }
    }
    func testSelectorRejectsUnknownFieldsDuplicateKeysAdjacentRoutesAndMalformedMultipart() async throws {
        let wire = Wire(), grant = Grant(), transport = try fence(wire,grant)
        var body = try ProjectEditContract.payload(draft(),topicID:nil,scope:.full); body["ownerId"] = .number(7)
        var duplicate = try json("api/publish/home",[:]); duplicate.httpBody = Data(#"{"id":1,"id":2}"#.utf8)
        var malformed = try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent("api/topic/edit-detail"),fields:["id":"71","scope":""],token:"synthetic-project-7")
        malformed.httpBody?.append(Data("extra".utf8))
        let requests = [try json(ProjectEditStoryContract.createPath,body),duplicate,malformed,try json("api/topic/delete",["id":.number(71)]),try json("api/approved-topic-release/v1/start",[:])]
        for request in requests { do { _ = try await transport.send(request); XCTFail() } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testClonePreservesFreshProjectGrantAndCannotRetainRevokedPermission() async throws {
        let wire = Wire(), grant = Grant(), transport = try fence(wire,grant), clone = transport.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        let request = try json("api/publish/home",[:]); _ = try await clone.send(request)
        grant.enabled = false; do { _ = try await clone.send(request); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,1)
    }
    func testOldConfirmationCannotReviveAfterRoleABAAndStorageOwnerIsStable() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant).makeSession(); await login(session)
        let old = session.projectEditor(product:.city); await old.load(); old.prepare(draft()); let confirmation = try XCTUnwrap(old.confirmation), owner = try XCTUnwrap(old.session)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        let current = try XCTUnwrap(old.session); XCTAssertNotEqual(current,owner); XCTAssertEqual(current.ownerKey,owner.ownerKey)
        let count = wire.requests.count; await old.confirm(confirmation); XCTAssertEqual(wire.requests.count,count); XCTAssertNil(old.confirmation)
        let fresh = session.projectEditor(product:.city); XCTAssertFalse(fresh === old); await fresh.load(); fresh.prepare(draft()); await fresh.confirm(try XCTUnwrap(fresh.confirmation))
        XCTAssertEqual(fresh.state,.acknowledged)
    }
    func testHeldOrdinaryPreflightLate401CannotLogOutReturnedRoleOrDispatchWrite() async throws {
        let wire = Wire(), grant = Grant(), vault = Vault(), session = try root(wire,grant,vault).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city); await editor.load(); editor.prepare(draft()); let confirmation = try XCTUnwrap(editor.confirmation)
        wire.holdHome = true; let started = expectation(description:"real creator preflight held"); wire.started = started
        let task = Task { await editor.confirm(confirmation) }; await fulfillment(of:[started],timeout:3)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount(); wire.finish401(); await task.value
        XCTAssertEqual(session.account?.id,7); XCTAssertEqual(session.account?.effectiveRole,"player"); XCTAssertEqual(vault.value,"synthetic-project-7")
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("/topic/v2/create") })
    }
    func testUnknownCreatorSubmissionRemainsLockedAcrossReentryAndExactRetryIsNotInvented() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant).makeSession(); await login(session)
        wire.failWrite = true; let editor = session.projectEditor(product:.city); await editor.load(); editor.prepare(draft()); await editor.confirm(try XCTUnwrap(editor.confirmation))
        XCTAssertEqual(editor.state,.unknown); XCTAssertTrue(editor.isLocked); let pending = try XCTUnwrap(editor.pending), count = wire.requests.count
        editor.leaveScreen(); await editor.load(); await editor.checkOutcome(); editor.prepare(draft())
        XCTAssertTrue(editor.isLocked); XCTAssertNil(editor.confirmation); XCTAssertEqual(wire.requests.count,count)
        var expected = pending; expected.dispatchStarted = true
        XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(editor.pending),expected))
    }
    func testHeldNormalPreflightCannotContinueAfterWriteOnlyGrantABA() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city); await editor.load(); editor.prepare(draft()); let confirmation = try XCTUnwrap(editor.confirmation), owner = try XCTUnwrap(editor.session)
        wire.holdHome = true; let started = expectation(description:"normal preflight before intent"); wire.started = started
        let task = Task { await editor.confirm(confirmation) }; await fulfillment(of:[started],timeout:3)
        let oldMount = session.projectEditorContextID
        session.withProjectEditConfigurationChange { grant.write = false }
        XCTAssertTrue(session.projectEditorIsConfigured) // Read remains approved.
        session.withProjectEditConfigurationChange { grant.write = true }
        XCTAssertNotEqual(session.projectEditorContextID,oldMount); XCTAssertEqual(editor.session?.ownerKey,owner.ownerKey)
        wire.finishHome(); await task.value; wire.holdHome = false
        XCTAssertNil(editor.pending); XCTAssertNil(editor.confirmation)
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("/topic/v2/create") })
        let fresh = session.projectEditor(product:.city); XCTAssertFalse(fresh === editor); await fresh.load(); fresh.prepare(draft()); await fresh.confirm(try XCTUnwrap(fresh.confirmation))
        XCTAssertEqual(fresh.state,.acknowledged)
    }
    func testQueuedNormalConfirmationCannotCrossGrantABAWithIdenticalRoutes() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city); await editor.load(); editor.prepare(draft()); let confirmation = try XCTUnwrap(editor.confirmation), before = wire.requests.count
        let task = Task { await editor.confirm(confirmation) }
        session.withProjectEditConfigurationChange { grant.write = false; grant.write = true }
        await task.value; XCTAssertEqual(wire.requests.count,before); XCTAssertNil(editor.pending); XCTAssertNil(editor.confirmation)
        XCTAssertNotEqual(session.projectEditor(product:.city).session?.configurationRevision,0)
    }
    func testCloneRejectsSuccessfulOldResponseAfterGrantGenerationABA() async throws {
        let wire = Wire(), grant = Grant(), transport = try fence(wire,grant), clone = transport.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        wire.holdHome = true; let started = expectation(description:"clone held approved read"); wire.started = started
        let request = try json("api/publish/home",[:]), task = Task { try await clone.send(request) }; await fulfillment(of:[started],timeout:3)
        grant.generation += 1; grant.write = false; grant.generation += 1; grant.write = true
        wire.finishHome(); do { _ = try await task.value; XCTFail("Old generation response must be rejected") } catch {}
        XCTAssertEqual(wire.requests.count,1); wire.holdHome = false; _ = try await clone.send(request); XCTAssertEqual(wire.requests.count,2)
    }
    func testMutationBoundaryStaysUnavailableThroughNestedChangesAndMissingOuterRevisionRejects() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant).makeSession(); await login(session)
        let original = try XCTUnwrap(session.projectEditor(product:.city).session)
        session.withProjectEditConfigurationChange {
            XCTAssertNil(session.projectEditor(product:.city).session); XCTAssertFalse(session.projectEditorIsConfigured)
            session.withProjectEditConfigurationChange { grant.write = false; XCTAssertNil(session.projectEditor(product:.city).session) }
            grant.write = true; XCTAssertNil(session.projectEditor(product:.city).session)
        }
        let fresh = try XCTUnwrap(session.projectEditor(product:.city).session); XCTAssertEqual(fresh.ownerKey,original.ownerKey); XCTAssertNotEqual(fresh,original)
        let transport = try fence(wire,grant); transport.projectEditConfigurationRevision = { nil }; let count = wire.requests.count
        do { _ = try await transport.send(json("api/publish/home",[:])); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
    }
    func testActualServiceFinalPreflightRejectsWriteOnlyABA_BEFORE_DurableDispatchMarker() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), original = try XCTUnwrap(editor.session), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage:storage)
        let transport = try fence(wire,grant), api = try APIConfiguration(baseURL:base)
        let approval = try OperationEndpointApproval(baseURL:base,namespace:original.storageNamespace,accountID:7,paths:[ProjectEditStoryContract.createPath])
        let service = ProjectEditHTTPService(configuration:api,transport:transport,owner:.personal,approval:approval,store:store,currentCredentials:{editor.session.flatMap { try? .init(session:$0,token:"synthetic-project-7") }})
        let operation = try ProjectEditPending(operationID:UUID(),ownerKey:original.ownerKey,identity:.init(),payload:ProjectEditContract.payload(draft(),topicID:nil,scope:.full))
        try store.savePending(operation,session:original)
        wire.holdHome = true; let started = expectation(description:"actual service final preflight"); wire.started = started
        let task = Task { await service.submit(operation,session:original) }; await fulfillment(of:[started],timeout:3)
        session.withProjectEditConfigurationChange { grant.write = false }; session.withProjectEditConfigurationChange { grant.write = true }
        wire.finishHome(); let result = await task.value; XCTAssertEqual(result,.notSent)
        let durable = try XCTUnwrap(store.pending(session:original,identity:operation.identity))
        XCTAssertTrue(ProjectEditLocalStore.exactPending(durable,operation)); XCTAssertNotEqual(durable.dispatchStarted,true)
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("/topic/v2/create") })
    }

}
