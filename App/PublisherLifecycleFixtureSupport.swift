import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit offline-only fixture. Never pass fixture grants or authority to a session host.
private actor PublisherLifecycleFixtureHTTP: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.lastPathComponent ?? ""
        let payload: String
        switch path {
        case "preview": payload = "{\"priceMin\":12.5,\"cityReferenceSampleSize\":0,\"lineup\":[{\"toType\":\"club\",\"toId\":9,\"shareMode\":1,\"shareRate\":20}]}"
        case "cancel_preview": payload = "{\"paidPlayers\":3}"
        case "xp-budget": payload = "{\"budget\":100,\"totalXp\":30,\"over\":false,\"remain\":70,\"perNode\":[{\"nodeId\":1,\"name\":\"Sample node\",\"xp\":30}]}"
        case "detail", "public-detail": payload = "{\"id\":9,\"name\":\"Offline sample partner\"}"
        case "apply": payload = "1"
        case "transfer-to-club": payload = "{\"newTopicId\":40}"
        default: payload = "null"
        }
        return (Data("{\"code\":200,\"msg\":\"Offline fixture only\",\"data\":\(payload)}".utf8), 200)
    }
}
@MainActor private final class PublisherLifecycleFixtureCenter: CreatorContentReading {
    let scope = UUID(); let isConfigured = true; let isAuthenticated = true; let isOfflineExample = true
    func center() async throws -> CreatorContentCenter { try JSONDecoder().decode(CreatorContentCenter.self, from: Data("{\"applyStatus\":\"not_applied\"}".utf8)) }
    func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage { .init(rows: [], total: 0) }
}
@MainActor private final class PublisherLifecycleFixtureJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = record }
    func clear(_ record: OperationPendingRecord) throws { records.removeValue(forKey: record.ownerKey + record.targetKey) }
}
@MainActor struct PublisherLifecycleFixtureRoot: View {
    private let client: PublisherLifecycleHTTP
    private let owner: PublisherLifecycleCoordinator
    private let application: CreatorApplicationCoordinator
    private let center: PublisherLifecycleFixtureCenter
    init() {
        let config = try! APIConfiguration(baseURL: URL(string: "https://example.com/offline/")!)
        let session = PublishingSession(namespace: "offline-lifecycle", accountID: 7, epoch: UUID(), role: "member", region: .china)
        let credential = try! PublishingCredentials(session: session, token: "offline-token")
        let grant = try! OperationEndpointApproval(baseURL: config.baseURL, namespace: session.namespace, accountID: 7, paths: ["api/topic/pricing/preview", "api/topic/pricing/confirm", "api/topic/cancel_preview", "api/activity/cancel_preview", "api/topic/cancel", "api/activity/cancel", "api/topic/xp-budget", "api/topic/transfer-to-club", "api/topic/beta/graduate", "api/creator/apply", "api/club/detail", "api/merchant/public-detail"])
        let client = PublisherLifecycleHTTP(configuration: config, transport: PublisherLifecycleFixtureHTTP(), grants: .init(reads: grant), credentials: { credential })
        self.client = client
        owner = PublisherLifecycleCoordinator(client: client, journal: PublisherLifecycleFixtureJournal()) { resource, _ in
            PublisherAuthority(resource: resource, ownerAccountID: 7, revision: "offline-fixture", beta: true, eligibleClubIDs: [9])
        }
        let center = PublisherLifecycleFixtureCenter(); self.center = center
        application = CreatorApplicationCoordinator(client: client, reader: center, journal: PublisherLifecycleFixtureJournal())
    }
    var body: some View {
        NavigationStack {
            List {
                Text("Offline examples · 离线示例")
                NavigationLink("Pricing · 定价") { PublisherPricingView(topicID: 4, client: client, coordinator: owner) }.accessibilityIdentifier("publisher.fixturePricing")
                NavigationLink("Cancellation · 取消退款") { PublisherCancellationView(resource: try! PublishedResource(kind: .topic, value: 4), coordinator: owner) }.accessibilityIdentifier("publisher.fixtureCancel")
                NavigationLink("Transfer · 移交") { PublisherOwnershipReviewView(action: .transfer(topicID: 4, clubID: 9), coordinator: owner) }
                NavigationLink("Graduate · 转正") { PublisherOwnershipReviewView(action: .graduate(topicID: 4), coordinator: owner) }
                NavigationLink("Creator application · 创作者申请") { CreatorApplicationView(coordinator: application, reader: center, onCenterRefresh: {}) }.accessibilityIdentifier("publisher.fixtureCreator")
                PublisherXPBudgetSection(topicID: 4, client: client)
            }
        }
    }
}
