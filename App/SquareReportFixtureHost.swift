#if DEBUG
import SwiftUI

@MainActor private final class SquareReportFixtureReader: SquareReading {
    var isConfigured: Bool { true }
    var isOfflineExample: Bool { true }
    var isSignedIn: Bool { true }
    let scope = UUID()
    private var version = 3
    private var subjectReads = 0
    func beginReportRead(scenario: String) {
        subjectReads += 1
        if scenario == "reportContentChanged", subjectReads > 1 { version = 4 }
    }
    private func post(id: Int = 701) throws -> SquarePost {
        let raw = SquareReportFixtures.postData(id: id, version: version)
        let text = String(data: raw, encoding: .utf8)!.replacingOccurrences(of: "Synthetic versioned community post", with: version == 3 ? "Synthetic versioned community post" : "Synthetic revised community post")
        return try JSONDecoder().decode(SquarePost.self, from: Data(text.utf8)).qualified(as: .communityV1)
    }
    func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage {
        try .init(items: [post()], hasMore: false)
    }
    // Legacy overloads deliberately refuse this fixture's v1 IDs.
    func squareDetail(id: Int) async throws -> SquarePost { throw APIError.invalidRequest }
    func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage { throw APIError.invalidRequest }
    func squareDetail(route: SquareContentRoute) async throws -> SquarePost {
        guard route.generation == .communityV1 else { throw APIError.invalidRequest }
        return try post(id: route.id)
    }
    func squareComments(route: SquareContentRoute, pageNumber: Int) async throws -> SquareCommentPage {
        guard route.generation == .communityV1 else { throw APIError.invalidRequest }
        return try .init(items: pageNumber == 1 ? SquareReportFixtures.comments(postID: route.id) : [], pageNumber: pageNumber, hasMore: false)
    }
}
@MainActor struct SquareReportFixtureHost: View {
    @State private var account = SocialAccountFixtureReader(.content)
    @State private var reader = SquareReportFixtureReader()
    @State private var reports: SquareReportCoordinator
    private let scenario: String
    @State private var epoch = 0
    init(scenario: String) {
        self.scenario = scenario
        let transport = SquareReportFixtureTransport(scenario: scenario)
        let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let service = scenario == "reportDisabled" ? SquareReportService(configuration: configuration, transport: transport)
            : SquareReportService(offlineConfiguration: configuration, transport: transport)
        _reports = State(initialValue: SquareReportCoordinator(service: service, journal: .ephemeral()))
    }
    var body: some View {
        let actions = SocialDisabledActionAccess(reader: reader, accountReader: account)
        let access = SquareReportSessionAccess(identity: {
            account.identity.accountID.map { .init(accountID: $0, epoch: account.identity.epoch, namespace: "square-report-synthetic") }
        }, token: { "synthetic-report-token" }, subject: { target in
            reader.beginReportRead(scenario: scenario)
            return try await actions.snapshot(target: target, generation: .communityV1)
        })
        VStack(spacing: 0) {
            Text(verbatim: scenario).font(.caption).accessibilityIdentifier("squareReport.fixture.scenario")
            Button("social.fixtureSwitchAccount") { account.switchAccount(); epoch += 1 }
                .accessibilityIdentifier("squareReport.fixture.switch")
            SquareBrowserView(reader: reader, accountReader: account, actions: SocialActionCoordinator(access: actions))
                .environment(\.squareReportContext, .init(coordinator: reports, access: access)).id(epoch)
        }
    }
}
#endif
