#if DEBUG
import SwiftUI
import Observation

/// Same real scoped adapter, synthetic transport, isolated journal. No production composition.
@MainActor @Observable final class ProfileFavoriteRemovalFixtureWire: HTTPTransport {
    var marked = true
    var writes = 0
    var reads = 0
    var scenario: String
    init(_ scenario: String) { self.scenario = scenario }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.lastPathComponent == "bookmark" {
            writes += 1
            if scenario == "unknown" { throw URLError(.timedOut) }
            if scenario == "ackUnreadable" { marked = false; return (Data(#"{"code":200}"#.utf8),200) }
            marked = false; return (Data(#"{"code":200}"#.utf8),200)
        }
        reads += 1
        if scenario == "readFailure", reads == 1 { throw URLError(.notConnectedToInternet) }
        if scenario == "ackUnreadable", writes > 0 { throw URLError(.timedOut) }
        return (Data("{\"code\":200,\"data\":{\"id\":101,\"isBookmarked\":\(marked ? 1 : 0)}}".utf8),200)
    }
}
@MainActor final class ProfileFavoriteRemovalFixtureJournal: OperationPendingJournal {
    var rows: [String: OperationPendingRecord] = [:]
    private func key(_ owner: String,_ target: String)->String { owner+"|"+target }
    func pending(ownerKey: String,targetKey: String) throws -> OperationPendingRecord? { rows[key(ownerKey,targetKey)] }
    func write(_ record: OperationPendingRecord) throws {
        guard rows[key(record.ownerKey,record.targetKey)] == nil else { throw APIError.invalidRequest }
        rows[key(record.ownerKey,record.targetKey)] = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        guard rows[key(record.ownerKey,record.targetKey)] == record else { throw APIError.invalidRequest }
        rows[key(record.ownerKey,record.targetKey)] = nil
    }
}
@MainActor @Observable final class ProfileFavoriteRemovalFixtureContext {
    var session: ProfileFavoriteRemovalSession?
    init(scope: UUID) {
        session = try! .init(identity:.init(accountID:81,epoch:1,role:"player"),namespace:"synthetic-favorite",collectionScope:scope,market:.china,token:"synthetic-not-a-credential")
    }
}
@MainActor struct ProfileFavoriteRemovalFixtureHost: View {
    private let scope: UUID
    private let context: ProfileFavoriteRemovalFixtureContext
    private let wire: ProfileFavoriteRemovalFixtureWire
    private let controller: ProfileFavoriteRemovalController
    private let post: SquarePost
    @State private var refreshed = false
    init(scenario: String = "success") {
        let scope = UUID(), context = ProfileFavoriteRemovalFixtureContext(scope: scope), wire = ProfileFavoriteRemovalFixtureWire(scenario)
        let config = try! APIConfiguration(baseURL: URL(string:"https://profile.example/native")!)
        let endpoint = try! OperationEndpointApproval(baseURL:config.baseURL,namespace:"synthetic-favorite",accountID:81,paths:ProfileFavoriteRemovalApproval.paths)
        let grant = try! ProfileFavoriteRemovalApproval(endpoint:endpoint,identity:context.session!.identity,postID:101,expiresAt:Date(timeIntervalSince1970:4102444800))
        self.scope=scope;self.context=context;self.wire=wire
        controller = .init(configuration:config,approvals:scenario == "disabled" ? [] : [grant],transport:wire,journal:ProfileFavoriteRemovalFixtureJournal(),current:{ context.session })
        post = try! JSONDecoder().decode(SquarePost.self,from:Data(#"{"id":101,"memberId":91,"contents":"Synthetic saved post"}"#.utf8)).qualified(as:.legacySquare)
    }
    var body: some View {
        NavigationStack {
            List {
                Text(verbatim:"Writes: \(wire.writes)").accessibilityIdentifier("profile.favoriteFixture.writes")
                Text(verbatim:"Reads: \(wire.reads)").accessibilityIdentifier("profile.favoriteFixture.reads")
                Button("Retire synthetic account") { context.session=nil }.accessibilityIdentifier("profile.favoriteFixture.retire")
                Button("Resolve synthetic server state") { wire.marked=false;wire.scenario="success" }.accessibilityIdentifier("profile.favoriteFixture.resolve")
                if refreshed { Text("Refreshed after verified removal").accessibilityIdentifier("profile.favoriteFixture.refreshed") }
                else {
                    Text(verbatim:post.contents ?? "")
                    ProfileFavoriteRemovalEntry(post:post,scope:scope,controller:controller,isCurrent:{ context.session?.collectionScope == scope },onRemoved:{ refreshed=true })
                }
            }
        }
    }
}
#endif
