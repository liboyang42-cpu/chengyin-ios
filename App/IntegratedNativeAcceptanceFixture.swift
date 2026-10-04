#if DEBUG
import SwiftUI

/// One sealed synthetic transport under AppSessionContainer -> SessionRootView.
/// This is compiled normal-UI acceptance with synthetic HTTP, never real-backend E2E.
/// No launch argument supplies a URL, credential, grant, permission or remote response.
@MainActor final class IntegratedNativeAcceptanceFixture: ObservableObject, HTTPTransport {
    enum Mode: String { case ready, denied }
    static let flag = "--uitesting-integrated-native"
    static let base = URL(string: "https://native-acceptance.example/native")!
    static let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.5)!, label: "Synthetic manual area")
    let mode: Mode
    let deployment: ReviewedAppDeployment
    let suiteName = "integrated-native-acceptance-" + UUID().uuidString
    let vault = Vault()
    private let recoveryAnchors = RecoveryAnchors()
    private let recoveryCiphertexts = RecoveryCiphertexts()
    private(set) var defaults: UserDefaults!
    weak var session: AppSession?
    @Published private(set) var ledger: [Entry] = []
    @Published private(set) var violations: [String] = []
    private var pendingAccount: Int?
    private var retained: Grants?

    struct Entry: Codable {
        let route: String
        let method: String
        let url: String
        let fields: [String: String]
        let accountID: Int?
        let role: String?
        let epoch: UInt64
        let namespace: String
        let token: String?
    }
    @MainActor final class Vault: AppTokenStorage {
        private(set) var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    // The normal activity view constructs a rich Play coordinator while rendering.
    // Keep that coordinator synthetic after durable Play is integrated, even when
    // this bounded journey opens only the read-only Play session destination.
    private actor RecoveryAnchors: ContentDraftAnchorStore {
        private var values: [String: ContentDraftAnchorItem] = [:]
        func read(slot: String) -> ContentDraftAnchorItem? { values[slot] }
        func insert(slot: String, item: ContentDraftAnchorItem) -> Bool {
            guard values[slot] == nil else { return false }; values[slot] = item; return true
        }
        func exchange(slot: String, matchingTag: Data, item: ContentDraftAnchorItem) -> Bool {
            guard values[slot]?.tag == matchingTag else { return false }; values[slot] = item; return true
        }
    }
    private actor RecoveryCiphertexts: ContentDraftCiphertextStore {
        private var values: [String: Data] = [:]
        private var presence: Set<String> = []
        func createPresence(slot: String) -> Bool { presence.insert(slot).inserted }
        func hasPresence(slot: String) -> Bool { presence.contains(slot) }
        func insert(name: String, bytes: Data) throws {
            guard values[name] == nil else { throw ContentDraftIssue.storageUnavailable }; values[name] = bytes
        }
        func readDurably(name: String, limit: Int) throws -> Data {
            guard let value = values[name], value.count <= limit else { throw ContentDraftIssue.storageUnavailable }; return value
        }
        func removeDurably(name: String) { values[name] = nil }
    }
    private struct Grants {
        let context: RuntimeDependencyContext
        let map: ManualMapReadApproval
        let orders: OwnedOrderReadApproval
        let play: RuntimeDependencyConfiguration
    }
    static func selected(arguments: [String]) -> IntegratedNativeAcceptanceFixture? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let mode = arguments.indices.contains(index + 1) ? Mode(rawValue: arguments[index + 1]) : nil
        return try! .init(mode: mode ?? .denied)
    }
    init(mode: Mode) throws {
        self.mode = mode
        deployment = try .init(market: .china, baseURL: Self.base.absoluteString,
            approvedBaseURLs: [.china: [Self.base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.integrated-acceptance", realm: "synthetic",
            reads: mode == .ready ? [.homeAndSearch, .manualMap, .playNodesAndRouteState] : [.homeAndSearch],
            contentDetails: mode == .ready ? .activityAndTopic : nil)
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }
    func makeComposition() -> AppCompositionRoot {
        .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { [vault] _ in vault },
                playRecovery: .synthetic(anchors: recoveryAnchors, ciphertexts: recoveryCiphertexts)),
            makeTransport: { self }, sessionDependencies: { context in
                guard let grants = self.grants(context) else { return .dormant }
                return .init(configuration: grants.play)
            }, manualMapReadApproval: { self.grants($0)?.map }, ownedOrderReadApproval: { self.grants($0)?.orders })
    }
    private func grants(_ context: RuntimeDependencyContext) -> Grants? {
        guard mode == .ready, let session, let account = session.account,
              [7, 8].contains(account.id), account.effectiveRole == "player",
              context.market == .china, context.baseURL == Self.base, context.role == "player",
              context.session.accountID == account.id, context.session.epoch == session.sessionRevision,
              context.session.namespace == deployment.storageScope.service,
              context.session.token == "synthetic-\(account.id)", context.session.token == vault.value else { return nil }
        if let retained, ContentDraftContextFence.matches(retained.context, context) { return retained }
        retained?.orders.revoke()
        let expires = Date().addingTimeInterval(600)
        guard let map = try? ManualMapReadApproval(context: context, expiresAt: expires),
              let orders = try? OwnedOrderReadApproval(context: context, expiresAt: expires),
              let endpoints = try? OperationEndpointApproval(baseURL: Self.base, namespace: context.session.namespace,
                accountID: account.id, paths: ["api/play/nodes", "api/play/route-state"]) else { return nil }
        // A stable issuance is retained per exact account/session context. No write capabilities.
        let value = Grants(context: context, map: map, orders: orders,
            play: .init(market: .china, endpoints: endpoints, play: [.reads], playReadApprovalID: UUID()))
        retained = value
        return value
    }
    var evidence: String {
        struct Evidence: Encodable {
            let ledger: [Entry]
            let violations: [String]
            let accountID: Int?
            let role: String?
            let epoch: UInt64
            let tokenStored: Bool
            let manualArea: Bool
        }
        let value = Evidence(ledger: ledger, violations: violations, accountID: session?.account?.id,
            role: session?.account?.effectiveRole, epoch: session?.sessionRevision ?? 0,
            tokenStored: vault.value != nil, manualArea: session?.roamArea != nil)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
    private func reject(_ reason: String) throws -> Never {
        violations.append(reason)
        throw APIError.invalidRequest
    }
    private func matchesForm(_ request: URLRequest, fields: [String: String]) -> Bool {
        let prefix = "multipart/form-data; boundary="
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              let url = request.url, url.query == nil, url.fragment == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let contentType = request.value(forHTTPHeaderField: "Content-Type"), contentType.hasPrefix(prefix),
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields,
                token: request.value(forHTTPHeaderField: "Authorization"), boundary: String(contentType.dropFirst(prefix.count))) else { return false }
        return request.httpBody == canonical.httpBody
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let url = request.url, let session, url.scheme == Self.base.scheme, url.host == Self.base.host,
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              url.path.hasPrefix("/native/api/"), request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json" else { try reject("origin") }
        let path = String(url.path.dropFirst("/native/".count))
        var canonicalURL = URLComponents(url: url, resolvingAgainstBaseURL: false)
        canonicalURL?.query = nil
        guard canonicalURL?.url?.absoluteString == Self.base.appendingPathComponent(path).absoluteString else { try reject("canonical URL") }
        let token = request.value(forHTTPHeaderField: "Authorization")
        var fields: [String: String] = [:]
        let route: String
        let json: String
        if path == "api/sms/send" {
            guard session.account == nil, token == nil else { try reject("SMS identity") }
            if matchesForm(request, fields: ["phone": "10000000000"]) { fields = ["phone": "10000000000"] }
            else if matchesForm(request, fields: ["phone": "10000000001"]) { fields = ["phone": "10000000001"] }
            else { try reject("SMS shape") }
            route = "sms-send"; json = #"{"code":200}"#
        } else if path == "api/login/phone" {
            guard session.account == nil, token == nil else { try reject("login identity") }
            let owner: Int
            if matchesForm(request, fields: ["phone": "10000000000", "code": "123456"]) { owner = 7 }
            else if matchesForm(request, fields: ["phone": "10000000001", "code": "123456"]) { owner = 8 }
            else { try reject("phone shape") }
            pendingAccount = owner; route = "phone"
            fields = ["phone": owner == 7 ? "10000000000" : "10000000001", "code": "123456"]
            json = "{\"code\":200,\"token\":\"synthetic-\(owner)\",\"data\":{\"id\":\(owner),\"role\":\"player\"}}"
        } else if path == "api/userInfo" {
            guard let owner = pendingAccount, token == "synthetic-\(owner)", session.account == nil,
                  request.httpMethod == "POST", request.httpBody == nil, url.query == nil,
                  request.value(forHTTPHeaderField: "Accept") == "application/json",
                  request.value(forHTTPHeaderField: "Content-Type") == nil else { try reject("account readback") }
            route = "userInfo"; pendingAccount = nil
            json = "{\"code\":200,\"appUser\":{\"userId\":\(owner),\"role\":\"player\",\"nickname\":\"Synthetic owner \(owner)\"}}"
        } else if path == "api/logout" {
            guard session.account == nil, vault.value == nil, session.roamArea == nil,
                  ["synthetic-7", "synthetic-8"].contains(token ?? ""), matchesForm(request, fields: [:]) else { try reject("logout isolation") }
            retained?.orders.revoke(); retained = nil; pendingAccount = nil
            route = "logout"; json = #"{"code":200}"#
        } else {
            guard let owner = session.account?.id, [7, 8].contains(owner), session.account?.effectiveRole == "player",
                  token == "synthetic-\(owner)", token == vault.value else { try reject("complete current identity") }
            switch path {
            case "api/common/banner":
                fields = ["showType": "1", "linkType": "0"]; route = "home.banners"; json = #"{"code":200,"data":[]}"#
            case "api/category/list":
                fields = ["parentid": "0"]; route = "home.categories"; json = #"{"code":200,"data":[]}"#
            case "api/topic/list":
                let normal = ["is_my": "0", "pageNum": "1", "pageSize": "10"]
                let recommended = normal.merging(["is_recommend": "1"]) { _, new in new }
                if matchesForm(request, fields: recommended) { fields = recommended; route = "home.recommended" }
                else { fields = normal; route = "home.stream" }
                json = #"{"code":200,"data":{"rows":[]}}"#
            case "api/activity/list":
                let nearby = ["is_my": "0", "sort_type": "2", "pageNum": "1", "pageSize": "6"]
                if matchesForm(request, fields: nearby) {
                    fields = nearby; route = "home.nearby"
                    json = #"{"code":200,"data":{"rows":[{"id":21,"name":"Synthetic activity card"}]}}"#
                } else {
                    fields = ["is_my": "2", "pageNum": "1", "pageSize": "6"]; route = "home.upcoming"
                    json = #"{"code":200,"data":{"rows":[]}}"#
                }
            case "api/activity/info":
                fields = ["id": "21"]; route = "activity-detail"
                json = #"{"code":200,"data":{"id":21,"name":"Synthetic activity detail","description":"Integrated normal navigation","omsTicketList":[]}}"#
            case "api/roam/pois":
                guard session.roamArea == Self.area,
                      ManualMapReadRoute(request: request, baseURL: Self.base, area: Self.area) == .places,
                      url.query == "lat=31.2&lng=121.5&radius=3000" else { try reject("manual map shape") }
                route = "map.places"
                json = #"{"code":200,"data":[{"id":42,"name":"Synthetic manual place","type":2,"lat":31.2,"lng":121.5}]}"#
            case "api/play/nodes", "api/play/route-state":
                guard request.httpMethod == "GET", request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil,
                      url.query == "activityId=21" else { try reject("play shape") }
                route = path.hasSuffix("/nodes") ? "play-nodes" : "play-route"
                let graph = #"{"routeMode":"BRANCH_GRAPH","sessionId":99,"version":1,"status":"ACTIVE","nodeStates":{"1":"PLAYABLE","2":"HIDDEN"}}"#
                json = route == "play-nodes" ? "{\"code\":200,\"data\":{\"topicId\":71,\"topicName\":\"Synthetic read-only play\",\"registered\":true,\"playable\":true,\"nodes\":[{\"nodeId\":1,\"name\":\"Visible synthetic node\"},{\"nodeId\":2,\"name\":\"Hidden synthetic node\"}],\"routeState\":\(graph)}}" : "{\"code\":200,\"data\":\(graph)}"
            case "api/registration/list":
                fields = ["owner_type": "3"]; route = "orders.list"
                json = "{\"code\":200,\"data\":{\"rows\":[{\"id\":41,\"memberId\":\(owner),\"cmsActivity\":{\"name\":\"Owner \(owner) list snapshot\"}}],\"total\":1}}"
            case "api/registration/info":
                fields = ["id": "41"]; route = "orders.detail"
                json = "{\"code\":200,\"data\":{\"id\":41,\"memberId\":\(owner),\"cmsActivity\":{\"name\":\"Owner \(owner) fresh detail\"},\"registrationStatus\":2,\"paymentStatus\":0,\"payableAmount\":12.3456,\"pointsReturned\":0,\"refundApplication\":{\"payoutStatus\":0}}}"
            default: try reject("unreviewed endpoint: " + path)
            }
            if request.httpMethod != "GET", !matchesForm(request, fields: fields) { try reject("exact form: " + path) }
            if request.httpMethod == "GET", !path.hasPrefix("api/play/"), path != "api/roam/pois" { try reject("unexpected GET") }
        }
        ledger.append(.init(route: route, method: request.httpMethod ?? "", url: url.absoluteString, fields: fields,
            accountID: session.account?.id, role: session.account?.effectiveRole, epoch: session.sessionRevision,
            namespace: deployment.storageScope.service, token: token))
        return (Data(json.utf8), 200)
    }
}

/// Readback only: no fixture navigation, authentication buttons or session shortcuts.
@MainActor struct IntegratedNativeAcceptanceEvidence: View {
    @ObservedObject var fixture: IntegratedNativeAcceptanceFixture
    @ObservedObject var session: AppSession
    var body: some View {
        Text(verbatim: "Synthetic normal-root acceptance")
            .font(.caption2).frame(maxWidth: .infinity).background(.regularMaterial)
            .accessibilityIdentifier("integratedAcceptance.evidence")
            .accessibilityValue(Text(verbatim: fixture.evidence))
    }
}
#endif
