import XCTest
@testable import Questify

/// Real AppSession factories and the outer transport, with synthetic HTTP only.
@MainActor final class TemplateShelfReadCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func root(_ wire: Wire, _ grants: Grants, _ vault: Vault) throws -> AppCompositionRoot {
        let suite = "shelf-reads-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.shelf-reads", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, templateShelfReadApproval: { grants.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    @MainActor private final class Grants {
        var enabled = true, freeze = false; var retained: TemplateShelfReadApproval?
        func select(_ context: RuntimeDependencyContext) -> TemplateShelfReadApproval? {
            guard enabled else { return nil }
            if !freeze, retained == nil || !ContentDraftContextFence.matches(retained?.context, context) {
                retained?.revoke(); retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(600))
            }
            return retained
        }
    }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    func testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session); wire.requests = []
        let coordinator = session.templateShelfCoordinator()
        XCTAssertTrue(coordinator.canRead); XCTAssertFalse(coordinator.canSubmit)
        let localEditor = session.templateAuthoringEditor()
        XCTAssertFalse(localEditor.canRead); XCTAssertFalse(localEditor.canSubmit)
        await coordinator.shelfReader.refresh(); XCTAssertEqual(coordinator.shelfReader.rows.map(\.id), [41]); XCTAssertTrue(coordinator.rows.isEmpty)
        let detail = try await session.makeOwnedMemberTemplateReader().memberTemplate(id: MemberPlayTemplateID(rawValue: 41)!)
        XCTAssertEqual(detail.memberID, 7)
        XCTAssertEqual(wire.requests.compactMap { TemplateShelfReadRoute(request: $0, baseURL: base) }, [.page(1, keyword: ""), .detail(MemberPlayTemplateID(rawValue: 41)!)])
        let count = wire.requests.count
        await coordinator.loadMine(); XCTAssertTrue(coordinator.rows.isEmpty)
        coordinator.prepareShelf(templateID: 41, action: .remove); XCTAssertNil(coordinator.shelfReview)
        XCTAssertEqual(wire.requests.count, count); XCTAssertFalse(coordinator.canSubmit)
    }
    func testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
        let editor = session.templateAuthoringEditor(); editor.change(.init(title: "Unsaved local draft"))
        XCTAssertEqual(editor.draft.title, "Unsaved local draft")
        _ = session.templateShelfCoordinator(); grants.retained?.revoke(); grants.enabled = false
        _ = session.templateShelfCoordinator()
        let afterRevocation = session.templateAuthoringEditor()
        XCTAssertTrue(editor === afterRevocation); XCTAssertEqual(afterRevocation.draft.title, "Unsaved local draft")
        grants.retained = nil; grants.enabled = true; _ = session.templateShelfCoordinator()
        let afterReissue = session.templateAuthoringEditor()
        XCTAssertTrue(editor === afterReissue); XCTAssertEqual(afterReissue.draft.title, "Unsaved local draft")
        XCTAssertFalse(afterReissue.canSubmit); XCTAssertFalse(afterReissue.canRead)
    }
    func testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail() async throws {
        let wire = Wire(); wire.pagedLegacy = true
        let session = try root(wire, Grants(), Vault()).makeSession(); await login(session); wire.requests = []
        let coordinator = session.templateShelfCoordinator(); await coordinator.shelfReader.refresh(keyword: "legacy")
        for _ in 2...11 { await coordinator.shelfReader.loadMore() }
        XCTAssertEqual(coordinator.shelfReader.rows.count, 110)
        XCTAssertTrue(coordinator.shelfReader.rows.contains { $0.id == 101 })
        XCTAssertEqual(coordinator.shelfReader.page, 11); XCTAssertFalse(coordinator.shelfReader.hasMore)
        XCTAssertTrue(coordinator.rows.isEmpty); XCTAssertFalse(coordinator.canSubmit)
        let reader = session.makeOwnedMemberTemplateReader(), id = try XCTUnwrap(MemberPlayTemplateID(rawValue: 101))
        let detail = try await reader.memberTemplate(id: id)
        XCTAssertEqual(detail.id, id); XCTAssertEqual(detail.memberID, 7)
        XCTAssertEqual(detail.story.first?.images, ["https://images.test/legacy.jpg"])
        XCTAssertEqual(wire.requests.compactMap { TemplateShelfReadRoute(request: $0, baseURL: base) },
            (1...11).map { .page($0, keyword: "legacy") } + [.detail(id)])
        let ownerHost = session.makeOwnedTemplateConfigurationHost(); await ownerHost.load(id: id)
        XCTAssertEqual(ownerHost.snapshot?.id, id); XCTAssertEqual(ownerHost.snapshot?.story.first?.images, ["https://images.test/legacy.jpg"])
        // A matching search row is not owner proof for a fresh detail response.
        wire.detailOwner = 8
        do { _ = try await reader.memberTemplate(id: id); XCTFail("Non-owner legacy story was accepted") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(wire.requests.count, 14)
        await ownerHost.load(id: id); XCTAssertNil(ownerHost.snapshot)
        XCTAssertEqual(wire.requests.count, 15)
        XCTAssertFalse(coordinator.canSubmit)
    }
    func testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
        let editor = session.templateAuthoringEditor(); editor.change(.init(title: "Keep unsaved local draft"))
        wire.requests = []; let host = session.makeOwnedTemplateConfigurationHost()
        await host.load(id: MemberPlayTemplateID(rawValue: 41)!)
        XCTAssertEqual(host.snapshot?.accountID, 7); XCTAssertNotNil(host.snapshot)
        XCTAssertTrue(session.templateAuthoringEditor() === editor)
        XCTAssertEqual(editor.draft.title, "Keep unsaved local draft"); XCTAssertFalse(editor.canSubmit)
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(TemplateShelfReadRoute(request: try XCTUnwrap(wire.requests.first), baseURL: base), .detail(MemberPlayTemplateID(rawValue: 41)!))
        grants.retained?.revoke(); XCTAssertNil(host.snapshot)
        grants.retained = nil; _ = session.templateShelfViewIdentity
        await host.load(id: MemberPlayTemplateID(rawValue: 41)!); XCTAssertNil(host.snapshot)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(editor.draft.title, "Keep unsaved local draft")
    }
    func testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let session = try root(wire, grants, Vault()).makeSession()
        await session.templateShelfCoordinator().shelfReader.refresh(); XCTAssertTrue(wire.requests.isEmpty)
        await login(session); wire.requests = []
        let disabled = session.templateShelfCoordinator(); XCTAssertFalse(disabled.canRead)
        await disabled.shelfReader.refresh(); XCTAssertTrue(wire.requests.isEmpty)
        grants.enabled = true
        let coordinator = session.templateShelfCoordinator(), reader = session.makeOwnedMemberTemplateReader()
        await coordinator.shelfReader.refresh(); XCTAssertEqual(coordinator.shelfReader.rows.count, 1)
        let identity = session.templateShelfViewIdentity
        grants.retained?.revoke(); grants.enabled = false
        XCTAssertNotEqual(identity, session.templateShelfViewIdentity); XCTAssertFalse(reader.isConfigured)
        await coordinator.shelfReader.refresh(); XCTAssertTrue(coordinator.shelfReader.rows.isEmpty)
        let count = wire.requests.count
        grants.retained = nil; grants.enabled = true; _ = session.templateShelfViewIdentity
        await coordinator.shelfReader.refresh(); XCTAssertEqual(wire.requests.count, count)
        do { _ = try await reader.memberTemplate(id: MemberPlayTemplateID(rawValue: 41)!); XCTFail() } catch {}
        await session.templateShelfCoordinator().shelfReader.refresh(); XCTAssertEqual(wire.requests.count, count + 1)
    }
    func testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges() async throws {
        for target in ["shelf", "detail", "ownerConfiguration"] {
            for transition in ["owner", "roleABA", "sessionABA", "revoke", "reissue", "expire", "cancel"] {
                for code in [200, 401, -1] {
                    let wire = Wire(), grants = Grants(), vault = Vault(), session = try root(wire, grants, vault).makeSession(); await login(session)
                    let coordinator = session.templateShelfCoordinator(), reader = session.makeOwnedMemberTemplateReader()
                    let ownerHost = session.makeOwnedTemplateConfigurationHost()
                    let paused = expectation(description: "template read suspended"); wire.pause = true; wire.onPaused = { paused.fulfill() }
                    let task = Task { () -> Bool in
                        if target == "shelf" { await coordinator.shelfReader.refresh(); return !coordinator.shelfReader.rows.isEmpty }
                        if target == "ownerConfiguration" { await ownerHost.load(id: MemberPlayTemplateID(rawValue: 41)!); return ownerHost.snapshot != nil }
                        do { _ = try await reader.memberTemplate(id: MemberPlayTemplateID(rawValue: 41)!); return true } catch { return false }
                    }
                    await fulfillment(of: [paused], timeout: 2)
                    switch transition {
                    case "owner": await session.logout(); wire.account = 8; await login(session)
                    case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
                    case "sessionABA": await session.logout(); await login(session)
                    case "revoke": grants.retained?.revoke(); grants.enabled = false
                    case "reissue": grants.retained?.revoke(); grants.retained = nil; _ = session.templateShelfViewIdentity
                    case "expire": let lease = try XCTUnwrap(grants.retained); lease.expireIfNeeded(now: lease.expiresAt)
                    default: task.cancel()
                    }
                    wire.finish(code: code); let applied = await task.value
                    XCTAssertFalse(applied, "\(target) \(transition) \(code)")
                    XCTAssertEqual(session.account?.id, wire.account); XCTAssertEqual(vault.value, "synthetic-\(wire.account)")
                }
            }
        }
    }
    func testCurrent401ExpiresOnlyCurrentOwner() async throws {
        for inspector in [false, true] {
            let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault).makeSession(); await login(session)
            wire.code = 401
            if inspector { await session.makeOwnedTemplateConfigurationHost().load(id: MemberPlayTemplateID(rawValue: 41)!) }
            else { await session.templateShelfCoordinator().shelfReader.refresh() }
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
        }
    }
    func testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations() async throws {
        let wire = Wire(), grants = Grants(), root = try root(wire, grants, Vault()).transport()
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        let clone = root.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        let page = try pageRequest(), detail = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/template/myinfo"), fields: ["id": "41"], token: "synthetic-7")
        _ = try await clone.send(page); _ = try await clone.send(detail)
        let count = wire.requests.count
        var invalid: [URLRequest] = []
        for path in ["draft", "publish", "delete", "updateLibraryStatus", "41/market-submit", "info", "list"] {
            var request = page; request.url = base.appendingPathComponent("api/template/" + path); invalid.append(request)
        }
        var request = page; request.url = base.appendingPathComponent("api/common/dict"); invalid.append(request)
        invalid.append(try TemplateAuthoringWireRequestBuilder.make(TemplateAuthoringContract.listMine(), configuration: .init(baseURL: base), token: "synthetic-7"))
        for url in ["https://evil.test/native/api/template/my-list", "https://example.test/other/api/template/my-list", "https://example.test/native/api/template/my-list?scope=merchant"] { var request = page; request.url = URL(string: url); invalid.append(request) }
        request = page; request.setValue("wrong-token", forHTTPHeaderField: "Authorization"); invalid.append(request)
        for request in invalid { do { _ = try await clone.send(request); XCTFail() } catch {} }
        for identity in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 8, role: "player", token: "synthetic-7"), .init(epoch: 2, accountID: 7, role: "player", token: "synthetic-7"), .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7"), .init(epoch: 1, accountID: nil, role: nil, token: nil)] {
            grants.freeze = true; root.current = { identity }
            do { _ = try await clone.send(page); XCTFail() } catch {}
        }
        XCTAssertEqual(wire.requests.count, count)
    }
    func testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors() async throws {
        for transition in ["revoke", "replace", "expiry", "token", "roleABA"] {
            for code in [200, 401, -1] {
                let wire = Wire(), grants = Grants(), root = try root(wire, grants, Vault()).transport()
                root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
                let clone = root.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
                wire.pause = true; let paused = expectation(description: "clone suspended"); wire.onPaused = { paused.fulfill() }
                let task = Task { try await clone.send(pageRequest()) }; await fulfillment(of: [paused], timeout: 2)
                let lease = try XCTUnwrap(grants.retained)
                switch transition {
                case "revoke": lease.revoke()
                case "replace": grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
                case "expiry": lease.expireIfNeeded(now: lease.expiresAt)
                case "token": root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "rotated", viewerRevision: 1) }
                default: root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3) }
                }
                wire.finish(code: code)
                do { _ = try await task.value; XCTFail(transition) } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
            }
        }
    }
    private func pageRequest() throws -> URLRequest {
        try TemplateAuthoringWireRequestBuilder.make(TemplateOwnShelfPage.request(page: 1, keyword: ""), configuration: .init(baseURL: base), token: "synthetic-7")
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], account = 7, role = "player", code = 200, pause = false, onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?, pendingJSON = "{}"
        var pagedLegacy = false, detailOwner: Int?
        func finish(code: Int) { let saved = pending; pending = nil; if code == -1 { saved?.resume(throwing: APIError.httpStatus(503)); return }; saved?.resume(returning: (Data((code == 200 ? pendingJSON : "{\"code\":\(code)}").utf8), 200)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path, json: String
            if pagedLegacy, let route = TemplateShelfReadRoute(request: request, baseURL: URL(string: "https://example.test/native")!) {
                let payload: [String: Any]
                switch route {
                case .page(let page, _):
                    let rows = (1...10).map { ["id": (page - 1) * 10 + $0, "title": "Legacy search result", "memberId": account] as [String: Any] }
                    payload = ["rows": rows, "total": 110]
                case .detail(let id):
                    let story = String(decoding: try JSONSerialization.data(withJSONObject: [["text": "Old draft", "tag": "Opening", "img": "https://images.test/legacy.jpg"]]), as: UTF8.self)
                    payload = ["id": id.rawValue, "memberId": detailOwner ?? account, "storyJson": story]
                }
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload]), 200)
            }
            if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/my-list") { json = "{\"code\":\(code),\"data\":{\"rows\":[{\"id\":41,\"title\":\"Owned template\",\"memberId\":\(account)}],\"total\":1}}" }
            else { json = "{\"code\":\(code),\"data\":{\"id\":41,\"memberId\":\(account),\"title\":\"Fresh owned detail\"}}" }
            if path.contains("/template/"), pause { pendingJSON = json; return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(json.utf8), 200)
        }
    }
}
