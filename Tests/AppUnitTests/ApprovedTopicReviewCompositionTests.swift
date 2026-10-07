import XCTest
@testable import Questify

@MainActor final class ApprovedTopicReviewCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.com/native")!
    private final class Grant { var enabled = true; var allReview = false; var observation = false; var sources = false }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", requests: [URLRequest] = [], hold = false
        var started: XCTestExpectation?, continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/phone") == true { return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8),200) }
            if request.url?.path.hasSuffix("/userInfo") == true { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200) }
            if request.url?.path.hasSuffix("/review/sources") == true {
                if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
                return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": ApprovedTopicReviewCompositionTests.sourceChoices()]), 200)
            }
            if request.url?.path.hasSuffix("/review/current") == true {
                if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
                let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
                let fields = ApprovedTopicReviewSynthetic.observationFields(receipt:ApprovedTopicReviewSynthetic.receiptFields(command:body))
                return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200),"data":fields]),200)
            }
            if request.url?.path.hasSuffix("/review/submit") == true || request.url?.path.hasSuffix("/review/status") == true {
                let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
                return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": ApprovedTopicReviewSynthetic.receiptFields(command: body)]),200)
            }
            if request.url?.path.hasSuffix("/prepare") == true {
                if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
                var capture = ApprovedTopicReviewSynthetic.captureFields().object!, summary = capture["summary"]!.object!
                let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
                if let selected = body["sourceSelections"] { summary["selectedMerchantSources"] = selected; capture["summary"] = .object(summary) }
                return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": ProjectEditJSON.object(capture)]),200)
            }
            throw APIError.invalidRequest
        }
        func finish401() { let old = continuation; continuation = nil; old?.resume(returning: (Data(#"{"code":401}"#.utf8),401)) }
    }
    private func root(_ wire: Wire, _ grant: Grant, _ vault: Vault) throws -> AppCompositionRoot {
        let suite = "review-composition-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.review-composition", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }, sessionDependencies: { context in
            guard grant.enabled else { return .dormant }
            var paths: [BusinessRuntimeFeature: String] = [.approvedTopicReviewPrepare: ApprovedTopicReviewPath.prepare]
            if grant.allReview { paths[.approvedTopicReviewSubmit] = ApprovedTopicReviewPath.submit; paths[.approvedTopicReviewStatus] = ApprovedTopicReviewPath.status }
            if grant.sources { paths[.approvedTopicReviewSources] = ApprovedTopicReviewPath.sources }
            if grant.observation { paths[.approvedTopicReviewCurrent] = ApprovedTopicReviewPath.current }
            var routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]
            for (feature,path) in paths { guard let route = try? BusinessRuntimeRoute.post(path) else { return .dormant }; routes[feature] = [route] }
            guard let configuration = try? BusinessRuntimeConfiguration(market: context.market, baseURL: context.baseURL,
                namespace: context.session.namespace, accountID: context.session.accountID, routes: routes) else { return .dormant }
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
        let owner = try XCTUnwrap(editor.session), reader = try XCTUnwrap(editor.releaseReviewSource); wire.requests = []
        let value = try await reader.prepare(target(owner), session: owner)
        XCTAssertEqual(value.topicID,7901); XCTAssertEqual(value.name,"Test-only current review capture")
        XCTAssertEqual(wire.requests.count,1); XCTAssertEqual(wire.requests[0].url?.absoluteString,base.appendingPathComponent(ApprovedTopicReviewPath.prepare).absoluteString)
        XCTAssertFalse(reader.canSubmit(session: owner)); XCTAssertFalse(reader.canReadStatus(session: owner)); XCTAssertNil(editor.releasePublicationSource)
        grant.enabled = false; let count = wire.requests.count; XCTAssertFalse(reader.isCurrent(session: owner))
        do { _ = try await reader.prepare(target(owner), session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
    }
    func testOldNormalFactoryCannotBecomeCurrentAgainAfterRoleABAAndFreshFactoryWorks() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant, Vault()).makeSession(); await login(session)
        let oldEditor = session.projectEditor(product: .city); oldEditor.synchronizeSession(); let owner = try XCTUnwrap(oldEditor.session), old = try XCTUnwrap(oldEditor.releaseReviewSource)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertFalse(old.isCurrent(session: owner)); let count = wire.requests.count
        do { _ = try await old.prepare(target(owner), session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
        let currentEditor = session.projectEditor(product: .city); currentEditor.synchronizeSession(); XCTAssertFalse(currentEditor === oldEditor)
        let current = try XCTUnwrap(currentEditor.releaseReviewSource), currentOwner = try XCTUnwrap(currentEditor.session)
        XCTAssertTrue(current.isCurrent(session: currentOwner)); _ = try await current.prepare(target(currentOwner), session: currentOwner)
    }
    func testRealOuterHeldReadRejectsRoleABA401WithoutLoggingOutReturnedAccount() async throws {
        let wire = Wire(), grant = Grant(), vault = Vault(), session = try root(wire, grant, vault).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city); editor.synchronizeSession(); let owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), t = try target(owner)
        wire.hold = true; let started = expectation(description: "outer actual transport held"); wire.started = started
        let task = Task { try await source.prepare(t, session: owner) }; await fulfillment(of: [started],timeout:3)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        wire.finish401(); do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertEqual(session.account?.id,7); XCTAssertEqual(session.account?.effectiveRole,"player"); XCTAssertEqual(vault.value,"synthetic-7")
        XCTAssertFalse(source.isCurrent(session: owner))
    }
    func testDefaultOffNormalFactoryNeverCreatesInnerReleaseAuthority() async throws {
        let wire = Wire(), grant = Grant(); grant.enabled = false
        let session = try root(wire,grant,Vault()).makeSession(); XCTAssertNil(session.projectEditor(product:.city).releaseReviewSource)
        await login(session); wire.requests = []
        let editor = session.projectEditor(product:.city); XCTAssertNil(editor.releaseReviewSource); XCTAssertNil(editor.releasePublicationSource)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOuterCloneKeepsExactSelectorAndRejectsAdjacentRoutesUnknownFieldsAndRevocation() async throws {
        let wire = Wire(), grant = Grant(), composition = try root(wire,grant,Vault()), deployment = try XCTUnwrap(composition.reviewed)
        let fence = composition.transport(); fence.current = { .init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1) }
        fence.approvedReleaseConfigurationRevision = { 1 }
        fence.approvedReleaseConfiguration = { context in
            guard grant.enabled else { return nil }
            return try? .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace, accountID:7,
                routes:[.approvedTopicReviewPrepare:[try .post(ApprovedTopicReviewPath.prepare)]])
        }
        let clone = fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        let api = try APIConfiguration(baseURL:base)
        func request(_ path:String,_ fields:[String:ProjectEditJSON])throws->URLRequest { try OperationAdapterHTTP.json(configuration:api,path:path,body:JSONEncoder().encode(fields),token:"synthetic-7") }
        let fields:[String:ProjectEditJSON] = ["topicId":.number(7901),"observedAuditTaskId":.number(3301)]
        _ = try await clone.send(request(ApprovedTopicReviewPath.prepare,fields)); XCTAssertEqual(wire.requests.count,1)
        var invalid=fields;invalid["ownerId"] = .number(7)
        for value in [try request(ApprovedTopicReviewPath.prepare,invalid),try request("api/approved-topic-release/v1/start",fields),try request(ApprovedTopicReleasePublicationPath.publish,fields),try request("api/topic/v2/create",fields)] {
            do { _ = try await clone.send(value); XCTFail() } catch {}
        }
        grant.enabled = false;do { _ = try await clone.send(request(ApprovedTopicReviewPath.prepare,fields));XCTFail() }catch{}
        XCTAssertEqual(wire.requests.count,1);XCTAssertFalse(deployment.storageScope.service.isEmpty)
    }
    func testNormalFactorySubmitAndStatusUseOnlyTheirOwnFreshCapabilities() async throws {
        let wire = Wire(), grant = Grant(); grant.allReview = true
        let session = try root(wire, grant, Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city); editor.synchronizeSession(); let owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), origin = try target(owner)
        wire.requests = []; let capture = try await source.prepare(origin, session: owner), journal = ApprovedTopicReviewJournal(storage: ProjectEditMemoryStorage())
        let saved = try journal.begin(capture, origin: origin, expected: journal.read(session: owner, topicID: 7901), session: owner), record = try XCTUnwrap(saved.current)
        let receipt = try await source.submit(record, session: owner); XCTAssertEqual(receipt.auditTaskID, 4402); XCTAssertEqual(receipt.submittedTaskStatus, 0)
        let readback = try await source.status(record, session: owner); XCTAssertEqual(receipt, readback)
        XCTAssertEqual(wire.requests.map { $0.url!.absoluteString }, [ApprovedTopicReviewPath.prepare, ApprovedTopicReviewPath.submit, ApprovedTopicReviewPath.status].map { base.appendingPathComponent($0).absoluteString })
        grant.allReview = false; XCTAssertTrue(source.canPrepare(session: owner)); XCTAssertFalse(source.canSubmit(session: owner)); XCTAssertFalse(source.canReadStatus(session: owner))
        do { _ = try await source.submit(record, session: owner); XCTFail() } catch {}
        do { _ = try await source.status(record, session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 3)
    }

    func testRetiredReviewFactoryCannotBorrowNewSessionWhenSameCapabilitiesReturn() async throws {
        let wire = Wire(), grant = Grant(); grant.allReview = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let old = session.projectEditor(product:.city), original = try XCTUnwrap(old.session), source = try XCTUnwrap(old.releaseReviewSource)
        session.withProjectEditConfigurationChange { grant.allReview = false }; session.withProjectEditConfigurationChange { grant.allReview = true }
        let current = session.projectEditor(product:.city), owner = try XCTUnwrap(current.session), count = wire.requests.count
        XCTAssertEqual(original.ownerKey,owner.ownerKey); XCTAssertNotEqual(original,owner)
        XCTAssertFalse(source.canPrepare(session:owner)); XCTAssertFalse(source.canSubmit(session:owner)); XCTAssertFalse(source.canReadStatus(session:owner))
        do { _ = try await source.prepare(target(owner),session:owner); XCTFail() } catch {}; XCTAssertEqual(wire.requests.count,count)
        let fresh = try XCTUnwrap(current.releaseReviewSource); XCTAssertTrue(fresh.canPrepare(session:owner)); XCTAssertTrue(fresh.canSubmit(session:owner)); XCTAssertTrue(fresh.canReadStatus(session:owner))
        _ = try await fresh.prepare(target(owner),session:owner)
    }
    func testQueuedReviewClaimAfterSubmitGrantABAKeepsExactJournalAndSendsNothing() async throws {
        let wire = Wire(), grant = Grant(); grant.allReview = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), origin = try target(owner)
        let storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage:storage), flow = ApprovedTopicReviewFlow(origin:origin,session:owner,source:source,journal:journal,stillCurrent:{true})
        await flow.load(); guard case .ready(let capture) = flow.state else { return XCTFail() }
        let confirmation = try XCTUnwrap(flow.review(capture)), claim = try XCTUnwrap(flow.claim(confirmation)), before = storage.data, count = wire.requests.count
        let task = Task { await flow.submit(claim) }
        session.withProjectEditConfigurationChange { grant.allReview = false; grant.allReview = true }
        await task.value; XCTAssertEqual(wire.requests.count,count); XCTAssertEqual(storage.data,before); XCTAssertEqual(flow.state,.closed)
        XCTAssertNotNil(try journal.read(session:try XCTUnwrap(editor.session),topicID:7901).current)
    }

    func testNormalObservationFactoryUsesOnlyOriginalSixFieldsAndIndependentCurrentGrant() async throws {
        let wire = Wire(), grant = Grant(); grant.allReview = true; grant.observation = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), observer = try XCTUnwrap(source as? any ApprovedTopicReviewObserving), origin = try target(owner)
        let capture = try await source.prepare(origin,session:owner), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage:storage)
        let pending = try journal.begin(capture,origin:origin,expected:journal.read(session:owner,topicID:7901),session:owner), draft = try XCTUnwrap(pending.current)
        let receipt = try await source.submit(draft,session:owner), saved = try journal.record(receipt,expected:pending,session:owner), record = try XCTUnwrap(saved.current), before = storage.data
        let observed = try await observer.observe(record,session:owner); XCTAssertEqual(observed.status,.pending); XCTAssertEqual(observed.auditTaskID,4402); XCTAssertEqual(storage.data,before)
        let request = try XCTUnwrap(wire.requests.last); XCTAssertEqual(request.url!.absoluteString,base.appendingPathComponent(ApprovedTopicReviewPath.current).absoluteString)
        XCTAssertEqual(try JSONDecoder().decode([String:ProjectEditJSON].self,from:XCTUnwrap(request.httpBody)),record.command.fields)
        session.withProjectEditConfigurationChange { grant.observation = false }
        let next = session.projectEditor(product:.city), current = try XCTUnwrap(next.session), fresh = try XCTUnwrap(next.releaseReviewSource), freshObserver = try XCTUnwrap(fresh as? any ApprovedTopicReviewObserving)
        XCTAssertTrue(fresh.canPrepare(session:current)); XCTAssertFalse(freshObserver.canObserve(session:current)); XCTAssertFalse(observer.canObserve(session:current))
        let count = wire.requests.count; do { _ = try await freshObserver.observe(record,session:current); XCTFail() } catch {}; XCTAssertEqual(wire.requests.count,count)
    }
    func testNormalCurrentObservationLate401AfterGrantABACannotExpireSession() async throws {
        let wire = Wire(), grant = Grant(), vault = Vault(); grant.allReview = true; grant.observation = true
        let session = try root(wire,grant,vault).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), origin = try target(owner)
        let journal = ApprovedTopicReviewJournal(storage:ProjectEditMemoryStorage()), flow = ApprovedTopicReviewFlow(origin:origin,session:owner,source:source,journal:journal,stillCurrent:{true})
        await flow.load(); guard case .ready(let capture) = flow.state else { return XCTFail() }; await flow.submit(try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(capture)))))
        let saved = try XCTUnwrap(flow.snapshot); wire.hold = true; let started = expectation(description:"normal current observation held"); wire.started = started
        let task = Task { await flow.observeCurrent(saved) }; await fulfillment(of:[started],timeout:3)
        session.withProjectEditConfigurationChange { grant.observation = false; grant.observation = true }; wire.finish401(); await task.value
        XCTAssertEqual(flow.state,.closed); XCTAssertEqual(session.account?.id,7); XCTAssertEqual(vault.value,"synthetic-7"); XCTAssertEqual(try journal.read(session:owner,topicID:7901),saved)
    }


    private static func sourceChoices() -> ProjectEditJSON {
        let selected: ProjectEditJSON = .object(["memberTemplateId": .number(73), "source": .object(["kind": .string("MERCHANT_AI_TEMPLATE_SOURCE_V1"), "sourceId": .number(91), "sourceVersion": .number(1), "contentHash": .string(String(repeating: "a", count: 64))]), "merchantConfirmation": .object(["kind": .string("MERCHANT_STORE_FACTS_CONFIRMATION_V1"), "sourceId": .number(92), "sourceVersion": .number(1), "contentHash": .string(String(repeating: "b", count: 64))])])
        return .object(["contract": .string("questify.topic-release.merchant-source-choices.v1"), "templateIdNamespace": .string("CMS_MEMBER_TEMPLATE"), "currentness": .string("CONFIRMED_HISTORICAL_INPUTS"), "ownerMemberId": .number(7), "topicId": .number(7901), "observedAuditTaskId": .number(3301), "observedAuditTaskVersion": .number(0), "sourceConfigVersion": .number(1), "approvalProof": .bool(false), "publicationAuthority": .bool(false), "sources": .array([.object(["memberTemplateId": .number(73), "hasOlderConfirmations": .bool(false), "confirmations": .array([.object(["selection": selected, "templateTitle": .string("Synthetic shop draft"), "templateContentHash": .string(String(repeating: "c", count: 64)), "confirmedAtEpochMillis": .number(1700000000000)])])])])])
    }
    func testNormalSourceChoiceFactoryCarriesExactRefsThenReadsOnlySixFields() async throws {
        let wire = Wire(), grant = Grant(); wire.role = "merchant"; grant.sources = true; grant.allReview = true; grant.observation = true
        let session = try root(wire, grant, Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city); editor.synchronizeSession(); let owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), chooser = try XCTUnwrap(source as? any ApprovedTopicReviewSourceChoosing), origin = try target(owner)
        wire.requests = []; let choices = try await chooser.sources(origin, session: owner), selected = try XCTUnwrap(choices.groups.first?.confirmations.first?.selection)
        let capture = try await chooser.prepare(origin, selections: [selected], session: owner), journal = ApprovedTopicReviewJournal(storage: ProjectEditMemoryStorage())
        let pending = try journal.begin(capture, origin: origin, expected: journal.read(session: owner, topicID:7901), session: owner), record = try XCTUnwrap(pending.current)
        let receipt = try await source.submit(record,session:owner); _ = try await source.status(record,session:owner)
        let saved = try journal.record(receipt,expected:pending,session:owner), observer = try XCTUnwrap(source as? any ApprovedTopicReviewObserving); _ = try await observer.observe(XCTUnwrap(saved.current),session:owner)
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent },["sources","prepare","submit","status","current"])
        let bodies = try wire.requests.map { try JSONDecoder().decode([String:ProjectEditJSON].self,from:XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(bodies.map(\.count),[2,3,7,6,6]); XCTAssertEqual(bodies[1]["sourceSelections"],bodies[2]["sourceSelections"]); XCTAssertNil(bodies[3]["sourceSelections"]); XCTAssertNil(bodies[4]["sourceSelections"])
        XCTAssertNil(editor.releasePublicationSource)
    }
    func testNormalSourcePickerDefaultOffCannotBorrowExistingPrepareGrant() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), reader = try XCTUnwrap(editor.releaseReviewSource as? any ApprovedTopicReviewSourceChoosing), count = wire.requests.count
        XCTAssertFalse(reader.canReadSources(session:owner)); do { _ = try await reader.sources(target(owner),session:owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count,count)
    }
    func testRealSourceSelectionModelClaimsSynchronouslyAndOldControlsCannotQueueAfterBack() async throws {
        let wire = Wire(), grant = Grant(); grant.sources = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), origin = try target(owner)
        let flow = ApprovedTopicReviewFlow(origin:origin,session:owner,source:source,journal:.init(storage:ProjectEditMemoryStorage()),stillCurrent:{true}), model = ApprovedTopicReviewReadModel(flow:flow)
        await model.load(); guard case .selectingSources(let shown) = flow.state else { return XCTFail() }
        model.selectSource(shown.choices.groups[0].confirmations[0],from:shown); let count = wire.requests.count
        model.captureSources(shown); flow.close(); await Task.yield(); await Task.yield()
        XCTAssertEqual(wire.requests.count,count); XCTAssertEqual(flow.state,.closed)
    }
    func testSourceFactoryLate401AfterRoleABACannotExpireCurrentAccount() async throws {
        let wire = Wire(), grant = Grant(), vault = Vault(); grant.sources = true
        let session = try root(wire,grant,vault).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource as? any ApprovedTopicReviewSourceChoosing), origin = try target(owner)
        wire.hold = true; wire.started = expectation(description:"normal source read held"); let task = Task { try await source.sources(origin,session:owner) }; await fulfillment(of:[try XCTUnwrap(wire.started)],timeout:3)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount(); wire.finish401(); do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertEqual(session.account?.id,7); XCTAssertEqual(vault.value,"synthetic-7"); XCTAssertFalse(source.canReadSources(session:owner))
        wire.hold = false; let fresh = session.projectEditor(product:.city), freshOwner = try XCTUnwrap(fresh.session), freshSource = try XCTUnwrap(fresh.releaseReviewSource as? any ApprovedTopicReviewSourceChoosing)
        _ = try await freshSource.sources(target(freshOwner),session:freshOwner)
    }
    func testSourceConfigurationABARejectsQueuedCaptureAndFreshPickerRemainsAvailable() async throws {
        let wire = Wire(), grant = Grant(); grant.sources = true
        let session = try root(wire,grant,Vault()).makeSession(); await login(session)
        let editor = session.projectEditor(product:.city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.releaseReviewSource), origin = try target(owner), flow = ApprovedTopicReviewFlow(origin:origin,session:owner,source:source,journal:.init(storage:ProjectEditMemoryStorage()),stillCurrent:{true})
        await flow.load(); guard case .selectingSources(let shown) = flow.state else { return XCTFail() }; XCTAssertTrue(flow.selectSource(shown.choices.groups[0].confirmations[0],from:shown)); let claim = try XCTUnwrap(flow.claimSourceCapture(shown)), count = wire.requests.count
        session.withProjectEditConfigurationChange { grant.sources = false; grant.sources = true }; await flow.captureSources(claim); XCTAssertEqual(wire.requests.count,count)
        let fresh = session.projectEditor(product:.city), freshOwner = try XCTUnwrap(fresh.session), reader = try XCTUnwrap(fresh.releaseReviewSource as? any ApprovedTopicReviewSourceChoosing)
        _ = try await reader.sources(target(freshOwner),session:freshOwner)
    }


    func testOuterSourcesRouteRejectsExtraReferencesQueriesAndBorrowedCapabilities() async throws {
        let wire = Wire(), grant = Grant(), composition = try root(wire,grant,Vault()), fence = composition.transport(), api = try APIConfiguration(baseURL:base)
        fence.current = { .init(epoch:1,accountID:7,role:"merchant",token:"synthetic-7",viewerRevision:1) }; fence.approvedReleaseConfigurationRevision = { 1 }
        fence.approvedReleaseConfiguration = { context in try? .init(market:context.market,baseURL:context.baseURL,namespace:context.session.namespace,accountID:7,routes:[.approvedTopicReviewSources:[try .post(ApprovedTopicReviewPath.sources)],.approvedTopicReviewPrepare:[try .post(ApprovedTopicReviewPath.prepare)],.approvedTopicReviewStatus:[try .post(ApprovedTopicReviewPath.status)],.approvedTopicReviewCurrent:[try .post(ApprovedTopicReviewPath.current)]]) }
        func request(_ path:String,_ fields:[String:ProjectEditJSON])throws->URLRequest { try OperationAdapterHTTP.json(configuration:api,path:path,body:JSONEncoder().encode(fields),token:"synthetic-7") }
        let fields:[String:ProjectEditJSON] = ["topicId":.number(7901),"observedAuditTaskId":.number(3301)]
        _ = try await fence.send(request(ApprovedTopicReviewPath.sources,fields)); XCTAssertEqual(wire.requests.count,1)
        let selected = try XCTUnwrap(Self.sourceChoices().object?["sources"]?.array?.first?.object?["confirmations"]?.array?.first?.object?["selection"])
        var withRefs=fields; withRefs["sourceSelections"] = .array([selected]); var duplicate=withRefs;duplicate["sourceSelections"] = .array([selected,selected])
        var outcome=withRefs;outcome["observedAuditTaskVersion"] = .number(0);outcome["sourceConfigVersion"] = .number(1);outcome["snapshotHash"] = .string(String(repeating:"c",count:64));outcome["requestId"] = .string(UUID().uuidString)
        var query=try request(ApprovedTopicReviewPath.sources,fields);query.url=URL(string:query.url!.absoluteString+"?owner=7")
        var fragment=try request(ApprovedTopicReviewPath.sources,fields);fragment.url=URL(string:fragment.url!.absoluteString+"#ignored")
        var get=try request(ApprovedTopicReviewPath.sources,fields);get.httpMethod="GET"
        for invalid in [try request(ApprovedTopicReviewPath.sources,withRefs),try request(ApprovedTopicReviewPath.prepare,duplicate),try request(ApprovedTopicReviewPath.status,outcome),try request(ApprovedTopicReviewPath.current,outcome),try request(ApprovedTopicReviewPath.submit,outcome),query,fragment,get] {
            do { _ = try await fence.send(invalid); XCTFail() } catch {}
        }
        XCTAssertEqual(wire.requests.count,1)
    }

}
