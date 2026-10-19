#if DEBUG
import SwiftUI

/// One launch flag (`--uitesting-member-parity`) for every w2-03 offline page.
/// `--member-parity-page <page>` picks the page and `--member-parity-scenario` its data.
enum MemberParityFixture {
    static let flag = "--uitesting-member-parity"
    static var isSelected: Bool { ProcessInfo.processInfo.arguments.contains(flag) }
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

@MainActor struct MemberParityFixtureRouter: View {
    let page = MemberParityFixture.value("--member-parity-page") ?? "home"
    let scenario = MemberParityFixture.value("--member-parity-scenario") ?? "ready"
    var body: some View {
        switch page {
        case "privacy": OwnMediaFixtureHost(scenario: scenario)
        case "favorites": TopicUnlikeFixtureHost(scenario: scenario)
        case "earnings":
            NavigationStack {
                List {
                    WalletEarningsEmptyNote()
                    ForEach(["2026-01-05 09:00:00", "2026-01-04 23:00:00", "2025-12-31 08:00:00"], id: \.self) { raw in
                        if let day = WalletIncomeDay.make(raw, now: WalletIncomeDay.serverCalendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!) {
                            WalletIncomeDayText(day: day).accessibilityIdentifier("member.fixture.day.\(raw.prefix(10))")
                        }
                    }
                }
            }
        default: MemberHomeFixtureHost(scenario: scenario)
        }
    }
}

@MainActor final class MemberHomeFixtureReader: MemberHomeReading {
    var scope = UUID()
    var isSignedIn = true
    var isConfigured = true
    var roleInfoAvailable = true
    let scenario: String
    private(set) var identityReads = 0
    init(scenario: String) {
        self.scenario = scenario
        if scenario == "dormant" { isConfigured = false; roleInfoAvailable = false }
        if scenario == "guest" { isSignedIn = false }
    }
    func identity() async throws -> MemberIdentitySnapshot {
        identityReads += 1
        if scenario == "failure", identityReads == 1 { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(MemberIdentitySnapshot.self, from: Data(#"{"nickname":"Synthetic member","city":"Synthetic City","levelId":2,"friendNum":3,"followNum":12,"fansNum":8,"topicNum":1,"activityNum":2,"likeNum":0,"createTime":"2026-01-02 08:00:00"}"#.utf8))
    }
    func roleInfo() async throws -> MemberRoleInfo {
        if scenario == "failure" { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(MemberRoleInfo.self, from: Data(#"{"role":"player","permission":{"maxThemes":3,"canBranch":true,"withdrawable":true}}"#.utf8))
    }
}

@MainActor struct MemberHomeFixtureHost: View {
    let scenario: String
    @State private var reader: MemberHomeFixtureReader
    @State private var showsTickets = false
    private let account: Account
    init(scenario: String) {
        self.scenario = scenario
        _reader = State(initialValue: MemberHomeFixtureReader(scenario: scenario))
        account = try! JSONDecoder().decode(Account.self, from: Data(#"{"id":81,"nickname":"Synthetic account","role":"player","levelId":1}"#.utf8))
    }
    var body: some View {
        NavigationStack {
            Form {
                MemberIdentityCardSection(account: account, reader: reader, onOpenTickets: { showsTickets = true })
                MemberBenefitsSection(reader: reader, earningsDestination: { AnyView(Text(verbatim: "Synthetic earnings").accessibilityIdentifier("member.fixture.earnings")) })
            }
            .navigationTitle(Text(verbatim: "Member fixture"))
            .alert(Text(verbatim: "Synthetic ticket wallet"), isPresented: $showsTickets) { Button { } label: { Text(verbatim: "OK") } }
        }
    }
}
@MainActor final class OwnMediaFixtureReader: OwnMediaReading {
    var scope = UUID()
    var isSignedIn = true
    var isAvailable = true
    let scenario: String
    private(set) var reads = 0
    init(scenario: String) {
        self.scenario = scenario
        if scenario == "dormant" { isAvailable = false }
        if scenario == "guest" { isSignedIn = false }
    }
    func page(before cursor: Int64?) async throws -> OwnMediaPage {
        reads += 1
        switch scenario {
        case "failure" where reads == 1: throw APIError.httpStatus(503)
        case "denied": throw OwnMediaReadFailure.rejected(code: 403)
        case "empty": return try OwnMediaPage.decode(Data(#"{"code":200,"data":[]}"#.utf8), before: cursor)
        default: break
        }
        let ids: [Int64] = cursor == nil ? Array((151...200).reversed()) : [12, 11]
        let states = ["HOLD", "APPROVED", "REJECTED", "UNAVAILABLE"]
        let rows = ids.enumerated().map { index, id in
            "{\"assetId\":\(id),\"reviewState\":\"\(states[index % 4])\",\"mediaType\":\"IMAGE\"" +
                (index % 4 == 2 ? ",\"reviewReason\":\"Synthetic reason\"}" : "}")
        }.joined(separator: ",")
        return try OwnMediaPage.decode(Data("{\"code\":200,\"data\":[\(rows)]}".utf8), before: cursor)
    }
}

@MainActor struct OwnMediaFixtureHost: View {
    @State private var reader: OwnMediaFixtureReader
    init(scenario: String) { _reader = State(initialValue: OwnMediaFixtureReader(scenario: scenario)) }
    var body: some View {
        NavigationStack { SettingsPrivacyLocationView(mediaReader: reader) }
    }
}
/// Answers the unlike command and the like_list readback without any network.
private actor TopicUnlikeFixtureWire: HTTPTransport {
    let scenario: String
    private var sends = 0
    init(scenario: String) { self.scenario = scenario }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        sends += 1
        if request.url?.lastPathComponent == "like_list" { return (Data(#"{"code":200,"rows":[{"id":302}]}"#.utf8), 200) }
        switch scenario {
        case "unknown": throw URLError(.networkConnectionLost)
        case "rejected": return (Data(#"{"code":500,"msg":"Synthetic rejection"}"#.utf8), 200)
        default: return (Data(#"{"code":200,"msg":"ok"}"#.utf8), 200)
        }
    }
}

@MainActor struct TopicUnlikeFixtureHost: View {
    @State private var reader = AccountCollectionFixtureReader(scenario: .content)
    @State private var controller: TopicUnlikeController
    init(scenario: String) {
        let base = URL(string: "https://fixture.invalid/native")!
        let approvals = (try? TopicUnlikeApproval(endpoint: OperationEndpointApproval(baseURL: base, namespace: "fixture", accountID: 81,
            paths: TopicUnlikeApproval.paths), accountID: 81, expiresAt: .distantFuture)).map { [$0] } ?? []
        _controller = State(initialValue: TopicUnlikeController(configuration: try! APIConfiguration(baseURL: base),
            approvals: scenario == "dormant" ? [] : approvals, transport: TopicUnlikeFixtureWire(scenario: scenario),
            current: { try? TopicUnlikeSession(accountID: 81, epoch: 1, namespace: "fixture", market: .china, token: "fixture-token") }))
    }
    var body: some View {
        NavigationStack {
            AccountCollectionFavoritesView(reader: reader, onOpenTopic: { _ in })
                .environment(\.topicUnlikeController, controller)
        }
    }
}
#endif
