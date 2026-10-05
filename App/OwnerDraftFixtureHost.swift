#if DEBUG
import SwiftUI
import Observation

@MainActor final class OwnerDraftFixtureVault: AppTokenStorage {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}

/// All synthetic HTTP stays in process. This recorder never owns URLSession or real credentials.
@MainActor @Observable final class OwnerDraftFixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var mode: String
    var accountID = 7
    var role = "player"
    private var pendingReads: [CheckedContinuation<(Data, Int), Error>] = []
    var pending: CheckedContinuation<(Data, Int), Error>? { pendingReads.first }
    var pendingCount: Int { pendingReads.count }
    var onPaused: (() -> Void)?
    var pauseRestore = false
    private var pendingRestore: CheckedContinuation<(Data, Int), Error>?
    private var pendingRestoreResponse: (Data, Int)?
    func releaseRestore() {
        let continuation = pendingRestore, response = pendingRestoreResponse
        pendingRestore = nil; pendingRestoreResponse = nil; pauseRestore = false
        if let response { continuation?.resume(returning: response) }
    }
    func modules(id: Int) -> [String: Any]? {
        guard mode.hasPrefix("receipts-") else { return nil }
        let empty = mode == "receipts-empty" || mode == "receipts-notEnabled" || mode == "receipts-ownerOnly"
        let count = empty ? 0 : (mode == "receipts-capped" ? 50 : 1)
        let rows: [[String: Any]] = (0..<count).map { index in
            ["installationId": 700 + index, "targetDraftId": id, "installedTargetVersion": mode == "receipts-stale" ? 1 : 2,
             "installedAt": "2026-10-03T00:00:00.123456Z", "versionId": "synthetic-module-version",
             "contentHash": String(repeating: "a", count: 64), "termsHash": String(repeating: "b", count: 64),
             "installedTargetPayloadHash": mode == "receipts-unverifiable" ? NSNull() : ContentDraftRecord.hash("{}") as Any,
             "binding": mode == "receipts-unverifiable" ? "BINDING_UNVERIFIABLE" : (mode == "receipts-stale" ? "STALE_BINDING" : "EXACT_REVISION"),
             "evidenceKind": "HISTORICAL_INSTALLATION"]
        }
        return ["availability": mode == "receipts-notEnabled" ? "NOT_ENABLED" : (mode == "receipts-ownerOnly" ? "OWNER_ONLY" : "HISTORICAL_RECEIPTS_ONLY"),
                "receipts": rows, "hasMore": count == 50, "contentUseStatus": "POST_INSTALL_POLICY_UNAVAILABLE",
                "textPreviewAllowed": mode == "receipts-invalid", "editingAllowed": false, "exportAllowed": false,
                "publicationAllowed": false, "executionAllowed": false, "commercialUseAllowed": false]
    }
    var listCalls: Int { requests.filter { $0.url?.path.hasSuffix("content-draft/list") == true }.count }
    var restoreCalls: Int { requests.filter { $0.url?.path.hasSuffix("content-draft/restore") == true }.count }
    var mutationCalls: Int { requests.filter { ["save", "delete", "publish"].contains($0.url?.lastPathComponent ?? "") }.count }
    init(mode: String) { self.mode = mode }
    func record(id: Int = 11, type: String = "ACTIVITY") -> [String: Any] {
        ["id": id, "ownerMemberId": accountID, "businessType": type, "clientDraftKey": "synthetic-\(id)",
         "payloadJson": "{}", "payloadHash": ContentDraftRecord.hash("{}"), "status": "DRAFT", "version": 2,
         "updatedByDevice": "synthetic", "updateTime": "2026-10-03T08:00:00+08:00"]
    }
    func listResponse() throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": 200, "data": mode == "empty" ? [] : [record(), record(id: 12, type: "TOPIC")]]), 200)
    }
    func release(code: Int = 200) throws {
        let continuation = pendingReads.isEmpty ? nil : pendingReads.removeFirst(); mode = "ready"
        continuation?.resume(returning: code == 200 ? try listResponse() : (Data("{\"code\":\(code)}".utf8), 200))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url!.lastPathComponent
        if path == "phone" {
            return (Data("{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID)}}".utf8), 200)
        }
        if path == "userInfo" {
            return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}".utf8), 200)
        }
        if request.url!.path.hasSuffix("content-draft/list") {
            if mode == "loading" { return try await withCheckedThrowingContinuation { pendingReads.append($0); onPaused?() } }
            if mode == "error", listCalls == 1 { throw ContentDraftIssue.unavailable }
            if mode == "unauthorized" { return (Data("{\"code\":401}".utf8), 200) }
            return try listResponse()
        }
        if request.url!.path.hasSuffix("content-draft/restore") {
            if mode == "restore-error", restoreCalls == 1 { throw ContentDraftIssue.unavailable }
            let id = request.httpBody == Data("draft_id=12&scope=".utf8) ? 12 : 11
            var restored = record(id: id, type: id == 12 ? "TOPIC" : "ACTIVITY")
            if let modules = modules(id: id) { restored["installedModules"] = modules }
            let response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": restored]), 200)
            if pauseRestore {
                pendingRestoreResponse = response
                return try await withCheckedThrowingContinuation { pendingRestore = $0; onPaused?() }
            }
            return response
        }
        return (Data("{\"code\":200}".utf8), 200)
    }
}

@MainActor struct OwnerDraftFixtureHost: View {
    @StateObject private var session: AppSession
    @State private var recorder: OwnerDraftFixtureTransport
    private let guest: Bool
    init(mode: String) {
        guest = mode == "guest"
        let recorder = OwnerDraftFixtureTransport(mode: mode)
        _recorder = State(initialValue: recorder)
        let deployment = try! ReviewedAppDeployment(market: .china, baseURL: "https://draft-browser.example/native",
            approvedBaseURLs: [.china: ["https://draft-browser.example/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.owner-draft", realm: "synthetic")
        let context = RuntimeDependencyContext(market: .china, baseURL: deployment.regional.apiConfiguration!.baseURL, role: "player",
            session: try! .init(accountID: 7, epoch: 1, namespace: deployment.storageScope.service, token: "synthetic-7"))
        let approval = try! OwnerDraftReadApproval(grant: .init(context: context, ownerMemberID: 7, scope: .personal,
            routes: [.list, .restore], expiresAt: .distantFuture))
        let vault = OwnerDraftFixtureVault(), defaults = UserDefaults(suiteName: "owner-draft-ui-" + UUID().uuidString)!
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { recorder }, ownerDraftReadApproval: { _ in mode == "disabled" || mode == "guest" ? nil : approval })
        _session = StateObject(wrappedValue: root.makeSession())
    }
    var body: some View {
        Group {
            if let account = session.account { AccountView(account: account) }
            else { WelcomeView() }
        }
        .environmentObject(session)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--uitesting-max-text") ? .accessibility5 : .large)
        .task { if !guest {
            session.authChannels.cancel()
            await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        } }
        .safeAreaInset(edge: .bottom) {
            VStack {
                HStack {
                    Text(verbatim: session.account == nil ? "guest" : "signed-in").accessibilityIdentifier("ownerDraft.recorder.session")
                    Text(verbatim: recorder.requests.prefix(2).compactMap { $0.url?.lastPathComponent }.joined(separator: ","))
                        .accessibilityIdentifier("ownerDraft.recorder.authPaths")
                }
                HStack {
                    Text(verbatim: String(recorder.listCalls)).accessibilityIdentifier("ownerDraft.recorder.list")
                    Text(verbatim: String(recorder.restoreCalls)).accessibilityIdentifier("ownerDraft.recorder.restore")
                    Text(verbatim: String(recorder.mutationCalls)).accessibilityIdentifier("ownerDraft.recorder.mutations")
                    Text(verbatim: String(recorder.pendingCount)).accessibilityIdentifier("ownerDraft.recorder.pending")
                }
                if recorder.pending != nil {
                    Button { try? recorder.release() } label: { Text(verbatim: "Synthetic: release response") }
                        .accessibilityIdentifier("ownerDraft.fixture.release")
                }
                Button { session.setOwnerDraftPresentationActive(false); session.setOwnerDraftPresentationActive(true) } label: {
                    Text(verbatim: "Synthetic: replace lifetime")
                }.accessibilityIdentifier("ownerDraft.fixture.replace")
            }.font(.caption2)
        }
    }
}
#endif
