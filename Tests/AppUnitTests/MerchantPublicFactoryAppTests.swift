import XCTest
@testable import Questify

@MainActor final class MerchantPublicFactoryAppTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data(#"{"code":200,"data":{"id":31,"memberId":77,"npc":{"name":"Synthetic NPC"}}}"#.utf8), 200)
        }
    }
    final class Journal: OperationPendingJournal {
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { nil }
        func write(_ record: OperationPendingRecord) throws {}
        func clear(_ record: OperationPendingRecord) throws {}
    }
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class NormalWire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player", status = 200, hold = false
        var onHeld: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        let body = Data(#"{"code":200,"data":{"id":31,"memberId":77}}"#.utf8)
        func resume(status: Int) { let p = pending; pending = nil; p?.resume(returning: (body, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url!.lastPathComponent {
            case "phone": return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8), 200)
            case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
            default:
                if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
                return (body, status)
            }
        }
    }
    private func deployment(reads: Set<ReviewedAppDeployment.ReadGrant> = []) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://merchant-public.example/native",
            approvedBaseURLs: [.china: ["https://merchant-public.example/native"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.merchant.public", realm: "synthetic", reads: reads)
    }
    private func normal(_ wire: NormalWire, approved: Bool? = true, wrongAccount: Bool = false) throws -> AppSession {
        let suite = "merchant-public-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        return AppCompositionRoot(deployment: .reviewed(try deployment(reads: [.homeAndSearch])),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire },
            sessionDependencies: { context in
                guard let approved else { return .dormant }
                return .init(merchantPublicApproval: try? .init(market: context.market, baseURL: context.baseURL,
                    namespace: context.session.namespace, accountID: wrongAccount ? 8 : context.session.accountID,
                    publicHomeRead: approved))
            }).makeSession()
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func request(_ deployment: ReviewedAppDeployment, fields: [String: Int] = ["id": 31]) throws -> URLRequest {
        let api = try XCTUnwrap(deployment.regional.apiConfiguration)
        var r = URLRequest(url: api.baseURL.appendingPathComponent("api/merchant/public-home"))
        r.httpMethod = "POST"; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return r
    }
    private func scoped(_ transport: CompositionHTTPTransport, deployment: ReviewedAppDeployment,
                        identity: CompositionHTTPTransport.SessionIdentity, approved: Bool = true) throws -> CompositionHTTPTransport {
        let api = try XCTUnwrap(deployment.regional.apiConfiguration)
        let context = try MerchantPublicHostContext(market: .china, baseURL: api.baseURL,
            namespace: deployment.storageScope.service, accountID: identity.accountID,
            epoch: identity.epoch, role: identity.role, token: identity.token)
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: api.baseURL,
            namespace: deployment.storageScope.service, accountID: identity.accountID, publicHomeRead: approved)
        return transport.scopedForPublicMerchantHome(approval: approval, context: context)
    }
    func testNormalSignedInCompositionHonorsExplicitPublicHomeReadWithoutSendingToken() async throws {
        let wire = NormalWire(), session = try normal(wire); await login(session)
        wire.requests = []
        let reader = session.publicMerchantHomeContext.reader
        XCTAssertTrue(reader.isConfigured)
        let owner = try await reader.home(.ownerMemberID(PublicMerchantOwnerID(77)!))
        let row = try await reader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!))
        XCTAssertEqual(owner.memberId, 77); XCTAssertEqual(row.id, 31)
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertTrue(wire.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && !$0.httpShouldHandleCookies })
        XCTAssertEqual(session.account?.id, 7)
    }
    func testMissingFalseAndWrongAccountApprovalsRemainClosedDespiteGenericReadGrant() async throws {
        let flags: [Bool?] = [nil, false, true]
        for flag in flags {
            let wire = NormalWire(), session = try normal(wire, approved: flag, wrongAccount: flag == true)
            await login(session); wire.requests = []
            do { _ = try await session.publicMerchantHomeContext.reader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testUnscopedRootStillRejectsPublicHomeAndApprovedCloneCannotReadUnrelatedPath() async throws {
        let wire = NormalWire(), d = try deployment(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
        let viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        root.current = { viewer }; let r = try request(d)
        do { _ = try await root.send(r); XCTFail() } catch {}
        let child = try scoped(root, deployment: d, identity: viewer)
        for path in ["api/merchant/info", "api/ai/npc/merchant-chat", "api/user/info", "api/merchant/list"] {
            var other = r; other.url = d.regional.apiConfiguration!.baseURL.appendingPathComponent(path)
            do { _ = try await child.send(other); XCTFail(path) } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testPublicHomeEnvelopeRejectsMalformedFieldsCookiesTokensAndNoncanonicalBodies() async throws {
        let wire = NormalWire(), d = try deployment(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
        let viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        root.current = { viewer }; let child = try scoped(root, deployment: d, identity: viewer)
        let valid = try request(d)
        for body in [#"{"id":0}"#, #"{"id":-1}"#, #"{"id":"31"}"#, #"{"id":true}"#, #"{"id":31.0}"#,
                     #"{"id":31,"id":31}"#, #"{"id":31,"memberId":77}"#, #"{"id":31,"extra":1}"#, #"{"id":9223372036854775808}"#] {
            var r = valid; r.httpBody = Data(body.utf8)
            do { _ = try await child.send(r); XCTFail(body) } catch {}
        }
        for header in ["Authorization", "Proxy-Authorization", "Cookie"] {
            var r = valid; r.setValue("synthetic", forHTTPHeaderField: header)
            do { _ = try await child.send(r); XCTFail(header) } catch {}
        }
        for suffix in ["/", "?id=31", "#fragment"] {
            var r = valid; r.url = URL(string: valid.url!.absoluteString + suffix)
            do { _ = try await child.send(r); XCTFail(suffix) } catch {}
        }
        var cookie = valid; cookie.httpShouldHandleCookies = true
        do { _ = try await child.send(cookie); XCTFail() } catch {}
        var streamed = valid; streamed.httpBodyStream = InputStream(data: Data("{}".utf8))
        do { _ = try await child.send(streamed); XCTFail() } catch {}
        for method in ["GET", "PUT", "DELETE"] {
            var r = valid; r.httpMethod = method
            do { _ = try await child.send(r); XCTFail(method) } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testPublicHomeScopeRequiresExactApprovalDeploymentNamespaceAndAccount() async throws {
        let wire = NormalWire(), d = try deployment(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
        let viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        root.current = { viewer }
        let base = d.regional.apiConfiguration!.baseURL
        for kind in ["disabled", "namespace", "account", "deployment"] {
            let url = kind == "deployment" ? URL(string: "https://other.example/native")! : base
            let namespace = kind == "namespace" ? "other" : d.storageScope.service
            let account = kind == "account" ? 8 : 7
            let context = try MerchantPublicHostContext(market: .china, baseURL: url, namespace: namespace,
                accountID: account, epoch: 1, role: "player", token: "synthetic-7")
            let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: namespace,
                accountID: account, publicHomeRead: kind != "disabled")
            let child = root.scopedForPublicMerchantHome(approval: approval, context: context)
            do { _ = try await child.send(request(d)); XCTFail(kind) } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testPublicHomeScopeSurvivesUnderlyingReplacementButNotViewerRevision() async throws {
        let wire = NormalWire(), d = try deployment(), root = CompositionHTTPTransport(deployment: d, underlying: NormalWire())
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        root.current = { viewer }
        let child = try scoped(root, deployment: d, identity: viewer).replacingUnderlying(wire)
        _ = try await child.send(request(d)); XCTAssertEqual(wire.requests.count, 1)
        viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1)
        do { _ = try await child.send(request(d)); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testPublicHomeLateSuccessAnd401RejectChangedViewer() async throws {
        for kind in ["account", "viewer"] { for status in [200, 401] {
            let wire = NormalWire(), d = try deployment(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
            var viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
            root.current = { viewer }; let child = try scoped(root, deployment: d, identity: viewer)
            let started = expectation(description: "public home held"); wire.hold = true; wire.onHeld = { started.fulfill() }
            let r = try request(d), task = Task { try await child.send(r) }
            await fulfillment(of: [started], timeout: 2)
            viewer = kind == "account"
                ? .init(epoch: 2, accountID: 8, role: "player", token: "synthetic-8")
                : .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 2)
            wire.resume(status: status)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        } }
    }
    func testRoleOnlyABARefreshRebuildsNormalFactoryWithoutReusingOldScope() async throws {
        let wire = NormalWire(), session = try normal(wire); await login(session)
        let old = session.publicMerchantHomeContext.reader
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        let fresh = session.publicMerchantHomeContext.reader
        XCTAssertNotEqual(old.scope, fresh.scope); XCTAssertFalse(old.isConfigured)
        wire.requests = []
        do { _ = try await old.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await fresh.home(.legacyMerchantRowID(PublicMerchantRowID(31)!))
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testPublicHome401RemainsReadFailureWithoutSigningOutCurrentViewer() async throws {
        let wire = NormalWire(), session = try normal(wire); await login(session)
        wire.status = 401
        do { _ = try await session.publicMerchantHomeContext.reader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertEqual(session.account?.id, 7)
    }
    func testNormalDormantDependenciesAndAppHomeRemainUnconfigured() async throws {
        let d = NativeRuntimeDependencies.dormant, wire = Wire()
        XCTAssertNil(d.merchantPublicApproval); XCTAssertFalse(d.merchantNPCGrants.chatAllowed)
        let context = try MerchantPublicHostContext(market: .china, baseURL: URL(string: "https://example.com/")!, namespace: "fixture", epoch: 1)
        XCTAssertNil(d.makeMerchantPublicFactory(api: try .init(baseURL: context.baseURL), journal: Journal(), current: { context }))
        let session = AppSession(runtimeDependencies: .init(transport: wire))
        let reader = session.publicMerchantHomeContext.reader
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalDependencyFactoryConstructsApprovedGuestReaderUsingInjectedHTTP() async throws {
        let wire = Wire(), url = URL(string: "https://example.com/prod-api/")!
        let context = try MerchantPublicHostContext(market: .china, baseURL: url, namespace: "fixture", epoch: 1)
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: "fixture", publicHomeRead: true)
        let d = NativeRuntimeDependencies(transport: wire, merchantPublicApproval: approval)
        let factory = try XCTUnwrap(d.makeMerchantPublicFactory(api: APIConfiguration(baseURL: url), journal: Journal(), current: { context }))
        let home = try await factory.homeReader.home(.ownerMemberID(PublicMerchantOwnerID(77)!))
        XCTAssertEqual(home.id, 31); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertNil(wire.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(factory.chatGrants.chatAllowed)
    }
    func testNormalDependencyFactoryRejectsAccountMismatchAndRetainedContextChanges() async throws {
        let wire = Wire(), url = URL(string: "https://example.com/")!
        var context: MerchantPublicHostContext? = try .init(market: .china, baseURL: url, namespace: "fixture", accountID: 9, epoch: 1, role: "user", token: "fixture-token")
        let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: "fixture", accountID: 9, publicHomeRead: true)
        let d = NativeRuntimeDependencies(transport: wire, merchantPublicApproval: approval)
        let factory = try XCTUnwrap(d.makeMerchantPublicFactory(api: APIConfiguration(baseURL: url), journal: Journal(), current: { context }))
        context = try .init(market: .china, baseURL: url, namespace: "fixture", accountID: 10, epoch: 2, role: "user", token: "next-token")
        XCTAssertFalse(factory.homeReader.isConfigured)
        XCTAssertNil(d.makeMerchantPublicFactory(api: try .init(baseURL: url), journal: Journal(), current: { context }))
        do { _ = try await factory.homeReader.home(.legacyMerchantRowID(PublicMerchantRowID(31)!)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
}

#if DEBUG
@MainActor final class MerchantOnboardingFixtureCounterTests: XCTestCase {
    func testReviewAndCancelCannotDispatchOrResetMonotonicCounters() async throws {
        for scenario in ["rejected", "submit-unknown"] {
            let fixture = MerchantOnboardingFixture(name: scenario)
            let coordinator = MerchantOnboardingCoordinator(server: fixture)
            let model = MerchantOnboardingModel(coordinator: coordinator)
            model.reset(); await model.load(); await model.checkIdentity()
            guard case .loaded(.application(let application)) = coordinator.loadState else {
                return XCTFail("Expected authoritative rejected fixture application")
            }
            model.reapply(application)
            model.prepare()
            XCTAssertNotNil(model.confirmation)
            XCTAssertEqual(fixture.submissionCount, 0)
            XCTAssertEqual(fixture.uploadCount, 0)
            model.cancelConfirmation()
            XCTAssertNil(model.confirmation)
            XCTAssertEqual(fixture.submissionCount, 0)
            XCTAssertEqual(fixture.uploadCount, 0)
            model.prepare()
            let approved = try XCTUnwrap(model.confirmation)
            XCTAssertEqual(fixture.submissionCount, 0)
            await coordinator.confirm(approved)
            XCTAssertEqual(fixture.submissionCount, 1)
            XCTAssertEqual(fixture.uploadCount, 0)
            model.cancelConfirmation()
            model.reset(); await model.load()
            XCTAssertEqual(fixture.submissionCount, 1, "Cancel and readback must never erase a dispatch")
            XCTAssertEqual(fixture.uploadCount, 0)
            if scenario == "submit-unknown" {
                XCTAssertEqual(coordinator.submission, .outcomeUnknown)
            }
            fixture.replaceAccount()
            XCTAssertEqual(fixture.submissionCount, 1, "Counters remain monotonic even across account replacement")
        }
    }
    func testDiagnosticGateRejectsOrdinaryMissingAmbiguousAndOtherFixtureArguments() {
        let marker = "--uitesting-merchant-onboarding-fixture"
        let optIn = "--uitesting-merchant-onboarding-diagnostics"
        var emitted: [String] = []
        for arguments in [[], [optIn], [marker], [marker, "rejected"],
                          [marker, "identity-required", optIn], [marker, "unknown", optIn],
                          [marker, "rejected", marker, "submit-unknown", optIn],
                          [marker, "rejected", optIn, optIn]] {
            XCTAssertNil(MerchantOnboardingFixtureDiagnostics.make(arguments: arguments, emit: { emitted.append($0) }))
        }
        XCTAssertTrue(emitted.isEmpty)
        for scenario in ["rejected", "submit-unknown"] {
            XCTAssertNotNil(MerchantOnboardingFixtureDiagnostics.make(arguments: [marker, scenario, optIn], emit: { emitted.append($0) }))
        }
        XCTAssertTrue(emitted.isEmpty, "Creating a diagnostic sink must not emit an event")
    }
    func testDiagnosticEventsAreCappedAndReplaceOutOfRangeStepsWithAConstant() throws {
        var emitted: [String] = []
        let sink = try XCTUnwrap(MerchantOnboardingFixtureDiagnostics.make(arguments: [
            "--uitesting-merchant-onboarding-fixture", "rejected", "--uitesting-merchant-onboarding-diagnostics"
        ], emit: { emitted.append($0) }))
        sink.record(.reapplyEntered, busy: false, locked: false, editing: false, step: Int.max)
        for _ in 0..<40 { sink.record(.reapplyEdited, busy: false, locked: false, editing: true, step: 1) }
        XCTAssertEqual(emitted.count, 16)
        XCTAssertEqual(sink.evidence, emitted.joined(separator: " | "))
        XCTAssertLessThanOrEqual(sink.evidence.utf8.count, 3072)
        XCTAssertEqual(emitted.first, "MERCHANT_ONBOARDING_FIXTURE_DIAGNOSTIC event=reapplyEntered;busy=0;locked=0;editing=0;step=invalid")
        XCTAssertTrue(emitted.dropFirst().allSatisfy { $0 == "MERCHANT_ONBOARDING_FIXTURE_DIAGNOSTIC event=reapplyEdited;busy=0;locked=0;editing=1;step=1" })
        XCTAssertFalse(emitted.joined().contains(String(Int.max)))
    }
    func testDiagnosticReadsDoNotChangeRealDraftSubmissionOrFixtureCounters() async throws {
        let fixture = MerchantOnboardingFixture(name: "rejected")
        let coordinator = MerchantOnboardingCoordinator(server: fixture)
        let model = MerchantOnboardingModel(coordinator: coordinator)
        model.reset(); await model.load()
        guard case .loaded(.application(let application)) = coordinator.loadState else { return XCTFail("Expected original fixture application") }
        model.reapply(application)
        let originalDraft = model.draft, originalSubmission = coordinator.submission
        var emitted: [String] = []
        let sink = try XCTUnwrap(MerchantOnboardingFixtureDiagnostics.make(arguments: [
            "--uitesting-merchant-onboarding-fixture", "rejected", "--uitesting-merchant-onboarding-diagnostics"
        ], emit: { emitted.append($0) }))
        sink.record(.reapplyEdited, busy: model.isBusy, locked: coordinator.submission.isLocked, editing: model.isEditing, step: model.step)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(model.draft, originalDraft); XCTAssertEqual(model.step, 1); XCTAssertTrue(model.isEditing)
        XCTAssertEqual(coordinator.submission, originalSubmission)
        XCTAssertEqual(fixture.submissionCount, 0); XCTAssertEqual(fixture.uploadCount, 0)
    }
}
#endif
