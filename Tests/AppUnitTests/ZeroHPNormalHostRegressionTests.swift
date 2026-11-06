import XCTest
@testable import Questify

/// Actual AppCompositionRoot -> AppSession -> ProjectEdit coordinator -> author.
/// Transport responses are isolated protocol fixtures, not deployment approval.
@MainActor final class ZeroHPNormalHostRegressionTests: XCTestCase {
    private let base = URL(string: "https://zero-host.test/native")!
    private final class Grant { var input = false, write = false }
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player", account = 7, failWrite = false, holdMatrix = false
        var started: XCTestExpectation?, held: CheckedContinuation<(Data, Int), Error>?
        func matrix() throws -> Data {
            try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["schemaVersion": 1, "types": [], "addons": [],
                "constraints": [:], "legacyProofs": [:], "zeroHpPolicies": ["legacy": ["BLOCK_HP_COST", "CHALLENGE", "LEGACY_END", "BLOCK_PAID"],
                    "generic": ["BLOCK_HP_COST", "CHALLENGE", "BLOCK_PAID", "THEME_FAIL", "WAIT", "STEPS"]]]])
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-zero-host\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/publish/home") { return (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":3}}}"#.utf8), 200) }
            if path.hasSuffix("/support-matrix") {
                if holdMatrix { return try await withCheckedThrowingContinuation { held = $0; started?.fulfill() } }
                return (try matrix(), 200)
            }
            if path.hasSuffix("/myinfo") { return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["id": 41, "memberId": account, "canEdit": true, "delFlag": 0, "advancedConfigJson": "{}"]]), 200) }
            if path.hasSuffix("/topic/v2/create") {
                if failWrite { throw URLError(.timedOut) }
                return (Data(#"{"code":200,"data":{"topicId":7901,"auditTaskId":3301,"reviewState":"PENDING","published":true,"bundledTemplateIds":[41]}}"#.utf8), 200)
            }
            throw APIError.invalidRequest
        }
        func finishMatrix() throws { let old = held; held = nil; old?.resume(returning: (try matrix(), 200)) }
        var inputReads: Int { requests.filter { $0.url!.path.hasSuffix("/support-matrix") || $0.url!.path.hasSuffix("/myinfo") }.count }
        var writes: [URLRequest] { requests.filter { $0.url!.path.hasSuffix("/topic/v2/create") } }
    }
    private func configuration(_ context: RuntimeDependencyContext, _ grant: Grant) -> BusinessRuntimeConfiguration? {
        var routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [.projectRead: try! [.post("api/publish/home"), .post("api/topic/edit-detail")]]
        if grant.input { routes[.projectAuthorInputRead] = try? [ProjectAuthorInputReadRoute.support.businessRoute, ProjectAuthorInputReadRoute.template(41).businessRoute] }
        if grant.write { routes[.projectWrite] = try? [.post(ProjectEditStoryContract.createPath), .post(ProjectEditStoryContract.updatePath)] }
        return try? .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, routes: routes)
    }
    private func root(_ wire: Wire, _ grant: Grant) throws -> AppCompositionRoot {
        let name = "zero-host-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.zero." + UUID().uuidString.lowercased(), realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, sessionDependencies: { context in .init(businessConfiguration: self.configuration(context, grant)) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func model(_ session: AppSession) async -> ProjectEditModel {
        let model = ProjectEditModel(coordinator: session.projectEditor(product: .city)); await model.load()
        var draft = ProjectEditSyntheticFixtures.draft(product: .city); draft.preserved["publishMode"] = .string("pro")
        // Real source reader must see actual bound template 41 from this fixture.
        model.draft = draft; return model
    }
    private func settle(_ editor: NativeZeroHPAuthorController) async {
        for _ in 0..<100 where editor.busy { await Task.yield() }
        XCTAssertFalse(editor.busy)
    }
    func testDefaultProjectReadDoesNotGrantAuthorInputsOrServerWrites() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let model = await model(session), editor = NativeZeroHPAuthorController(model: model)
        editor.setSceneActive(true); editor.open(); await settle(editor)
        XCTAssertNil(editor.inputs); XCTAssertFalse(editor.canFinish); XCTAssertEqual(wire.inputReads, 0)
        XCTAssertFalse(model.coordinator.canSubmit); XCTAssertTrue(wire.writes.isEmpty)
    }
    func testDedicatedReadAllowsOriginalLocalSaveButNeverGrantsServerWrite() async throws {
        let wire = Wire(), grant = Grant(); grant.input = true
        let session = try root(wire, grant).makeSession(); await login(session)
        let model = await model(session), editor = NativeZeroHPAuthorController(model: model)
        editor.setSceneActive(true); editor.open(); await settle(editor); XCTAssertNotNil(editor.inputs)
        editor.mutate(editor.editToken) { value, _ in value.message("Exact e\u{301} reply") }
        let finished = await editor.finish(editor.editToken); XCTAssertTrue(finished)
        XCTAssertEqual(Array(try NativeZeroHPAuthorDraft(draft: model.draft).zeroMessage.utf8), Array("Exact e\u{301} reply".utf8))
        XCTAssertGreaterThan(wire.inputReads, 0); XCTAssertFalse(model.coordinator.canSubmit); XCTAssertTrue(wire.writes.isEmpty)
    }
    func testGrantRevocationAndReissueCannotReviveOriginalEditor() async throws {
        let wire = Wire(), grant = Grant(); grant.input = true
        let session = try root(wire, grant).makeSession(); await login(session)
        let model = await model(session), editor = NativeZeroHPAuthorController(model: model)
        editor.setSceneActive(true); editor.open(); await settle(editor); let token = editor.editToken
        let original = ProjectEditPendingMaterials.exactData(model.draft), reads = wire.inputReads
        session.withProjectEditConfigurationChange { grant.input = false }
        session.withProjectEditConfigurationChange { grant.input = true }
        let finished = await editor.finish(token); XCTAssertFalse(finished)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), original); XCTAssertEqual(wire.inputReads, reads)
        XCTAssertTrue(wire.writes.isEmpty)
    }
    func testBackgroundDuringRealInputReadDiscardsLateResult() async throws {
        let wire = Wire(), grant = Grant(); grant.input = true
        let session = try root(wire, grant).makeSession(); await login(session)
        let model = await model(session), editor = NativeZeroHPAuthorController(model: model)
        wire.holdMatrix = true; wire.started = expectation(description: "normal matrix read")
        editor.setSceneActive(true); editor.open(); await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 3)
        let original = ProjectEditPendingMaterials.exactData(model.draft)
        editor.setSceneActive(false); try wire.finishMatrix(); await settle(editor)
        XCTAssertNil(editor.inputs); XCTAssertNil(editor.staged); XCTAssertFalse(editor.canFinish)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), original); XCTAssertTrue(wire.writes.isEmpty)
    }
    func testAccountOrRoleChangeDuringInputReadCannotPublishOldSource() async throws {
        for accountChange in [false, true] {
            let wire = Wire(), grant = Grant(); grant.input = true
            let session = try root(wire, grant).makeSession(); await login(session)
            let model = await model(session), editor = NativeZeroHPAuthorController(model: model)
            wire.holdMatrix = true; wire.started = expectation(description: "old source held")
            editor.setSceneActive(true); editor.open(); await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 3)
            if accountChange { wire.account = 8 } else { wire.role = "merchant" }
            await session.refreshOwnAccount(); editor.retireIfInvalid(); try wire.finishMatrix(); await settle(editor)
            XCTAssertNil(editor.inputs); XCTAssertFalse(editor.canFinish); XCTAssertTrue(wire.writes.isEmpty)
        }
    }
    func testUnknownOriginalSaveKeepsExactPayloadAndBlocksAuthorReentry() async throws {
        let wire = Wire(), grant = Grant(); grant.input = true; grant.write = true; wire.failWrite = true
        let session = try root(wire, grant).makeSession(); await login(session)
        let model = await model(session), editor = NativeZeroHPAuthorController(model: model)
        editor.setSceneActive(true); editor.open(); await settle(editor)
        editor.mutate(editor.editToken) { value, _ in value.message("Original pending reply") }
        let saved = await editor.finish(editor.editToken); XCTAssertTrue(saved)
        model.coordinator.prepare(model.draft); let confirmation = try XCTUnwrap(model.coordinator.confirmation)
        await model.coordinator.confirm(confirmation)
        XCTAssertEqual(model.coordinator.state, .unknown); let original = try XCTUnwrap(model.coordinator.pending)
        XCTAssertEqual(original.payload["themeRuntimeConfig"], model.draft.preserved["themeRuntimeConfig"])
        editor.open(); XCTAssertNil(editor.staged); XCTAssertFalse(editor.canFinish)
        await model.coordinator.confirm(confirmation); await model.coordinator.checkOutcome()
        XCTAssertEqual(model.coordinator.pending?.operationID, original.operationID)
        XCTAssertEqual(model.coordinator.pending?.payload, original.payload); XCTAssertEqual(wire.writes.count, 1)
    }
}
