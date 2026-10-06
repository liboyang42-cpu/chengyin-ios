import XCTest
@testable import Questify

@MainActor final class ApprovedReleaseCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.com/native")!
    private final class Grant { var enabled = true; var publication = false; var revision: UInt64 = 1 }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", requests: [URLRequest] = [], hold = false
        var started: XCTestExpectation?, continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/phone") == true { return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8),200) }
            if request.url?.path.hasSuffix("/userInfo") == true { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200) }
            if request.url?.path.hasSuffix("/publish") == true || request.url?.path.hasSuffix("/status") == true {
                let command = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
                let fields: ProjectEditJSON = .object(["releaseId": .number(501), "topicId": command["topicId"]!, "sourceConfigVersion": .number(1), "auditTaskId": command["auditTaskId"]!, "auditRecordId": .number(81), "auditTaskVersion": command["auditTaskVersion"]!, "schemaVersion": .number(1), "manifestHash": command["expectedManifestHash"]!, "auditSnapshotHash": command["auditSnapshotHash"]!, "currentlyApproved": .bool(true)])
                return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": fields]),200)
            }
            if request.url?.path.hasSuffix("/prepare") == true {
                if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
                return (try ApprovedTopicReleaseSyntheticSource.preparationData(),200)
            }
            throw APIError.invalidRequest
        }
        func finishSuccess() throws { let prior = continuation; continuation = nil; prior?.resume(returning:(try ApprovedTopicReleaseSyntheticSource.preparationData(),200)) }
        func finish401() { let old = continuation; continuation = nil; old?.resume(returning: (Data(#"{"code":401}"#.utf8),401)) }
    }
    private func root(_ wire: Wire, _ grant: Grant, _ vault: Vault) throws -> AppCompositionRoot {
        let suite = "release-composition-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.release-composition", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }, sessionDependencies: { context in
            guard grant.enabled, let configuration = try? BusinessRuntimeConfiguration(market: context.market, baseURL: context.baseURL,
                namespace: context.session.namespace, accountID: context.session.accountID, routes: grant.publication ? [.approvedTopicReleasePrepare: [try .post(ApprovedTopicReleasePaths.prepare)], .approvedTopicReleasePublish: [try .post(ApprovedTopicReleasePublicationPath.publish)], .approvedTopicReleaseStatus: [try .post(ApprovedTopicReleasePublicationPath.status)]] : [.approvedTopicReleasePrepare: [try .post(ApprovedTopicReleasePaths.prepare)]]) else { return .dormant }
            return .init(businessConfiguration: configuration)
        })
    }
    private func login(_ session: AppSession) async { session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456"); XCTAssertEqual(session.account?.id,7) }
    private func target(_ session: ProjectEditSession) throws -> ApprovedTopicReleaseReadTarget {
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(7901), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(41)])]), expectedTopicID: nil)
        let pending = try ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full), completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: ack)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending, session: session))
    }
    func testNormalAppSessionFactoryReachesOnlyExactPrepareThroughOuterFence() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant, Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city); editor.synchronizeSession()
        let owner = try XCTUnwrap(editor.session), reader = try XCTUnwrap(editor.releasePreparationSource); wire.requests = []
        let value = try await reader.prepare(target(owner), session: owner)
        XCTAssertEqual(value.topicID,7901); XCTAssertEqual(value.name,"Synthetic server-approved title")
        XCTAssertEqual(wire.requests.count,1); XCTAssertEqual(wire.requests[0].url?.absoluteString,base.appendingPathComponent(ApprovedTopicReleasePaths.prepare).absoluteString)
        XCTAssertNil(editor.releasePublicationSource)
        grant.enabled = false; let count = wire.requests.count; XCTAssertFalse(reader.isCurrent(session: owner))
        do { _ = try await reader.prepare(target(owner), session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
    }
    func testOldNormalFactoryCannotBecomeCurrentAgainAfterRoleABAAndFreshFactoryWorks() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant, Vault()).makeSession(); await login(session)
        let oldEditor = session.projectEditor(product: .city); oldEditor.synchronizeSession(); let owner = try XCTUnwrap(oldEditor.session), old = try XCTUnwrap(oldEditor.releasePreparationSource)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertFalse(old.isCurrent(session: owner)); let count = wire.requests.count
        do { _ = try await old.prepare(target(owner), session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
        let currentEditor = session.projectEditor(product: .city); currentEditor.synchronizeSession(); XCTAssertFalse(currentEditor === oldEditor)
        let current = try XCTUnwrap(currentEditor.releasePreparationSource), currentOwner = try XCTUnwrap(currentEditor.session)
        XCTAssertTrue(current.isCurrent(session: currentOwner)); _ = try await current.prepare(target(currentOwner), session: currentOwner)
    }
    func testRealOuterHeldReadRejectsRoleABA401WithoutLoggingOutReturnedAccount() async throws {
        let wire = Wire(), grant = Grant(), vault = Vault(), session = try root(wire, grant, vault).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city); editor.synchronizeSession(); let owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releasePreparationSource), t = try target(owner)
        wire.hold = true; let started = expectation(description: "outer actual transport held"); wire.started = started
        let task = Task { try await source.prepare(t, session: owner) }; await fulfillment(of: [started],timeout:3)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        wire.finish401(); do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertEqual(session.account?.id,7); XCTAssertEqual(session.account?.effectiveRole,"player"); XCTAssertEqual(vault.value,"synthetic-7")
        XCTAssertFalse(source.isCurrent(session: owner))
    }
    func testDefaultOffNormalFactoryNeverCreatesInnerReleaseAuthority() async throws {
        let wire = Wire(), grant = Grant(); grant.enabled = false
        let session = try root(wire,grant,Vault()).makeSession(); XCTAssertNil(session.projectEditor(product:.city).releasePreparationSource)
        await login(session); wire.requests = []
        let editor = session.projectEditor(product:.city); XCTAssertNil(editor.releasePreparationSource); XCTAssertNil(editor.releasePublicationSource)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOuterCloneKeepsExactSelectorAndRejectsAdjacentRoutesUnknownFieldsAndRevocation() async throws {
        let wire = Wire(), grant = Grant(), composition = try root(wire,grant,Vault()), deployment = try XCTUnwrap(composition.reviewed)
        let fence = composition.transport(); fence.current = { .init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1) }
        fence.approvedReleaseConfigurationRevision = { grant.revision }
        fence.approvedReleaseConfiguration = { context in
            guard grant.enabled else { return nil }
            return try? .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace, accountID:7,
                routes:[.approvedTopicReleasePrepare:[try .post(ApprovedTopicReleasePaths.prepare)]])
        }
        let clone = fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        let api = try APIConfiguration(baseURL:base)
        func request(_ path:String,_ fields:[String:ProjectEditJSON])throws->URLRequest { try OperationAdapterHTTP.json(configuration:api,path:path,body:JSONEncoder().encode(fields),token:"synthetic-7") }
        let fields:[String:ProjectEditJSON] = ["topicId":.number(7901),"auditTaskId":.number(3301)]
        _ = try await clone.send(request(ApprovedTopicReleasePaths.prepare,fields)); XCTAssertEqual(wire.requests.count,1)
        var invalid=fields;invalid["ownerId"] = .number(7)
        for value in [try request(ApprovedTopicReleasePaths.prepare,invalid),try request("api/approved-topic-release/v1/start",fields),try request(ApprovedTopicReleasePublicationPath.publish,fields),try request("api/topic/v2/create",fields)] {
            do { _ = try await clone.send(value); XCTFail() } catch {}
        }
        grant.enabled = false;do { _ = try await clone.send(request(ApprovedTopicReleasePaths.prepare,fields));XCTFail() }catch{}
        XCTAssertEqual(wire.requests.count,1);XCTAssertFalse(deployment.storageScope.service.isEmpty)
    }
    func testOldPrepareAndPublicationFactoriesCannotBorrowNewGenerationSession() async throws {
        let wire = Wire(), grant = Grant(); grant.publication = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let old = session.projectEditor(product:.city), owner = try XCTUnwrap(old.session), reader = try XCTUnwrap(old.releasePreparationSource), publisher = try XCTUnwrap(old.releasePublicationSource)
        session.withProjectEditConfigurationChange { grant.publication = false }
        session.withProjectEditConfigurationChange { grant.publication = true }
        let fresh = session.projectEditor(product:.city), next = try XCTUnwrap(fresh.session), count = wire.requests.count
        XCTAssertNotEqual(owner,next); XCTAssertEqual(owner.ownerKey,next.ownerKey)
        XCTAssertFalse(reader.isCurrent(session:next)); XCTAssertFalse(publisher.canPublish(session:next)); XCTAssertFalse(publisher.canCheckStatus(session:next))
        do { _ = try await reader.prepare(target(next),session:next); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
        let currentReader = try XCTUnwrap(fresh.releasePreparationSource), currentPublisher = try XCTUnwrap(fresh.releasePublicationSource)
        let prepared = try await currentReader.prepare(target(next),session:next), journal = ApprovedTopicReleasePublicationJournal(storage:ProjectEditMemoryStorage())
        let saved = try journal.begin(prepared,expected:journal.read(session:next,topicID:7901),session:next), record = try XCTUnwrap(saved.current)
        let receipt = try await currentPublisher.publish(record,session:next), checked = try await currentPublisher.status(record,session:next)
        XCTAssertEqual(receipt,checked); XCTAssertEqual(receipt.releaseID,501)
    }
    func testHeldPreparationHealthyResponseAfterGrantABAIsRejectedWithoutLogout() async throws {
        let wire = Wire(), grant = Grant(), vault = Vault(), session = try root(wire,grant,vault).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releasePreparationSource), original = try target(owner)
        wire.hold = true; let started = expectation(description:"approved preparation held"); wire.started = started
        let task = Task { try await source.prepare(original,session:owner) }; await fulfillment(of:[started],timeout:3)
        session.withProjectEditConfigurationChange { grant.enabled = false; grant.enabled = true }
        try wire.finishSuccess(); do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertEqual(session.account?.id,7); XCTAssertEqual(vault.value,"synthetic-7"); XCTAssertFalse(source.isCurrent(session:try XCTUnwrap(editor.session)))
    }
    func testPublicationClaimSurvivesGrantRetirementWithoutQueuedDispatchOrLogDeletion() async throws {
        let wire = Wire(), grant = Grant(); grant.publication = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releasePublicationSource), reader = try XCTUnwrap(editor.releasePreparationSource)
        let prepared = try await reader.prepare(target(owner),session:owner), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage:storage)
        let flow = ApprovedTopicReleasePublishFlow(session:owner,topicID:7901,source:source,journal:journal,stillCurrent:{true})
        let confirmation = try XCTUnwrap(flow.review(prepared)), claim = try XCTUnwrap(flow.claim(confirmation)), before = storage.data, count = wire.requests.count
        let task = Task { await flow.submit(claim) }
        session.withProjectEditConfigurationChange { grant.publication = false; grant.publication = true }
        await task.value; XCTAssertEqual(wire.requests.count,count); XCTAssertEqual(storage.data,before); XCTAssertEqual(flow.state,.closed)
        XCTAssertNotNil(try journal.read(session:try XCTUnwrap(editor.session),topicID:7901).current)
    }
    func testOuterCloneRejectsBothReviewAndReleaseLateResponsesAcrossGenerationABA() async throws {
        for review in [false,true] {
            let wire = Wire(), grant = Grant(), composition = try root(wire,grant,Vault()), fence = composition.transport()
            fence.current = { .init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1) }
            let path = review ? ApprovedTopicReviewPath.prepare : ApprovedTopicReleasePaths.prepare
            let feature: BusinessRuntimeFeature = review ? .approvedTopicReviewPrepare : .approvedTopicReleasePrepare
            fence.approvedReleaseConfigurationRevision = { grant.revision }
            fence.approvedReleaseConfiguration = { context in guard grant.enabled else { return nil }; return try? .init(market:context.market,baseURL:context.baseURL,namespace:context.session.namespace,accountID:7,routes:[feature:[try .post(path)]]) }
            let clone = fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
            let taskKey = review ? "observedAuditTaskId" : "auditTaskId"
            let body:[String:ProjectEditJSON] = ["topicId":.number(7901), taskKey:.number(3301)]
            let request = try OperationAdapterHTTP.json(configuration:.init(baseURL:base),path:path,body:JSONEncoder().encode(body),token:"synthetic-7")
            wire.hold = true; let started = expectation(description:"outer clone held"); wire.started = started
            let task = Task { try await clone.send(request) }; await fulfillment(of:[started],timeout:3)
            grant.revision += 1; grant.enabled = false; grant.enabled = true; grant.revision += 1
            try wire.finishSuccess(); do { _ = try await task.value; XCTFail() } catch {}
            XCTAssertEqual(wire.requests.count,1); wire.hold = false; _ = try await clone.send(request); XCTAssertEqual(wire.requests.count,2)
            fence.approvedReleaseConfigurationRevision = { nil }; do { _ = try await clone.send(request); XCTFail() } catch {}; XCTAssertEqual(wire.requests.count,2)
        }
    }

}
