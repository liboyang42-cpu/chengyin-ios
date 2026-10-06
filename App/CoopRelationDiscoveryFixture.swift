#if DEBUG
import SwiftUI

/// Request accounting is observable only by its dedicated fixture label. A completed profile
/// read must not republish the identity owner that constructs the navigation environment.
@MainActor final class CoopRelationFixtureReadLedger: ObservableObject {
    @Published var reads = 0
    @Published var ownerReads = 0
    @Published var clubReads = 0
    @Published private(set) var diagnostic = ""
    private var events: [String] = []
    private var sequence = 0
    func record(_ value: String) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--cooperation-flow-fixture"), args.contains("--relation-discovery-fixture"),
              args.contains("--relation-scenario") else { return }
        sequence += 1
        events.append("\(sequence):" + String(value.prefix(160)))
        events = Array(events.suffix(32))
        diagnostic = events.joined(separator: " | ")
    }
}
@MainActor private struct CoopRelationFixtureReadCounter: View {
    @ObservedObject var ledger: CoopRelationFixtureReadLedger
    var body: some View {
        Text(verbatim: "\(ledger.ownerReads):\(ledger.clubReads)")
            .accessibilityIdentifier("cooprelation.fixture.profileReads")
            .accessibilityValue(ledger.diagnostic)
    }
}

@MainActor final class CoopRelationFixtureReader: ObservableObject, CoopFlowReading, ClubReading, PublicMerchantHomeReading {
    @Published var session: CoopFlowSession? = try! .init(accountID: 101, epoch: 1, token: "synthetic-relation")
    @Published var scope = UUID()
    let ledger = CoopRelationFixtureReadLedger()
    var reads: Int { ledger.reads }
    var ownerReads: Int { ledger.ownerReads }
    var clubReads: Int { ledger.clubReads }
    let scenario: String
    var failNext: Bool
    var clubIdentity: ClubReadIdentity { .init(accountID: session?.accountID, epoch: session?.epoch ?? 0) }
    let isClubConfigured = true
    let isConfigured = true
    let isOfflineExample = true
    init(scenario: String) { self.scenario = scenario; failNext = scenario == "retry" }
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        ledger.reads += 1
        if failNext { failNext = false; throw CoopFlowFailure.malformed }
        let merchant: CoopFlowJSON = .object(["id": .id(8), "memberId": .id(41), "name": .string("Synthetic merchant"), "coverImage": .string("https://relation-fixture.invalid/cover.jpg"), "logo": .string("https://relation-fixture.invalid/logo.jpg")])
        let invalid: CoopFlowJSON = .object(["id": .id(41), "name": .string("Missing owner")])
        let clubs: [CoopFlowJSON] = scenario == "empty" ? [] : [.object(["id": .id(9), "name": .string("Synthetic club"), "cover": .string("https://relation-fixture.invalid/club.jpg")])]
        return .object(["relations": .array([]), "discovery": .object([
            "merchants": .array(scenario == "clubs" || scenario == "empty" ? [] : [merchant, invalid, .null]), "clubs": .array(clubs)])])
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        guard target == .ownerMemberID(PublicMerchantOwnerID(41)!) else { throw PublicMerchantHomeFailure.invalid }
        ledger.ownerReads += 1
        ledger.record("owner.read count=\(ledger.ownerReads)")
        return try JSONDecoder().decode(PublicMerchantHome.self, from: Data(#"{"id":8,"memberId":41,"name":"Public owner 41","description":"Synthetic public merchant profile"}"#.utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        guard id == 9 else { throw CoopFlowFailure.unavailable }
        ledger.clubReads += 1
        ledger.record("club.read count=\(ledger.clubReads)")
        return try JSONDecoder().decode(ClubRecord.self, from: Data(#"{"id":9,"name":"Public club 9","description":"Synthetic public club profile","memberCount":0}"#.utf8))
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor struct CoopRelationFixtureHost: View {
    @StateObject private var reader: CoopRelationFixtureReader
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--relation-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "mixed"
        _reader = StateObject(wrappedValue: .init(scenario: scenario))
    }
    var body: some View {
        let scope = CoopRelationProfileScope(merchantScope: reader.scope, clubIdentity: reader.clubIdentity, sessionRevision: reader.session?.epoch ?? 0, contentRevision: 1)
        let current: () -> Bool = { reader.session != nil && reader.scope == scope.merchantScope && reader.clubIdentity == scope.clubIdentity }
        let profiles = CoopRelationProfileContext(scope: scope, isCurrent: current, canOpen: { _ in current() }, destination: { route, selectionCurrent in
            switch route {
            case .merchant(let owner):
                return AnyView(PublicMerchantHomeView(target: .ownerMemberID(owner), context: .init(reader: CoopRelationMerchantReader(base: reader, owner: owner, isCurrent: { current() && selectionCurrent() }))))
            case .club(let id): return AnyView(CoopRelationClubProfileHost(id: id, base: reader, isCurrent: { current() && selectionCurrent() }))
            }
        }, debugTrace: { reader.ledger.record($0) })
        VStack {
            VStack(spacing: 8) {
                CoopRelationFixtureReadCounter(ledger: reader.ledger)
                Button("Change synthetic identity") {
                    reader.ledger.record("identity.replace.received")
                    reader.session = try! .init(accountID: 102, epoch: 2, token: "replacement"); reader.scope = UUID()
                    reader.ledger.record("identity.replace.completed")
                }
                    .accessibilityIdentifier("cooprelation.fixture.replace")
                Button("Sign out synthetic identity") {
                    reader.ledger.record("identity.signout.received")
                    reader.session = nil; reader.scope = UUID()
                    reader.ledger.record("identity.signout.completed")
                }
                    .accessibilityIdentifier("cooprelation.fixture.signOut")
            }
            // Keep harness chrome readable without consuming the product's accessibility5 viewport.
            // The stack and real discovery/profile content still inherit the requested large size.
            .dynamicTypeSize(.large)
            NavigationStack {
                CooperationFlowWorkbench(reader: reader)
            }
            // Own the destination dependency above the navigation stack. Attaching
            // it only to the workbench leaves pushed entries with the nil fallback.
            .environment(\.cooperationRelationDiscovery, { flow in
                AnyView(CoopRelationDiscoveryView(reader: flow, profiles: profiles,
                    displayContext: .init(topicID: 3, topicName: "Synthetic topic context", chapterID: 5)))
            })
        }.dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--uitesting-large-text") ? .accessibility5 : .large)
    }
}
#endif
