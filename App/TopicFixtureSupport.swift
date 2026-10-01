#if DEBUG
import SwiftUI

@MainActor final class TopicFixtureReader: TopicReading {
    enum Scenario: String { case content, empty, failure, unauthorized, unconfigured, unavailable, closed }
    let scenario: Scenario
    let scope = UUID()
    var isConfigured: Bool { scenario != .unconfigured }
    var isOfflineExample: Bool { true }
    init(scenario: Scenario = .content) { self.scenario = scenario }
    private func check() throws {
        switch scenario {
        case .failure: throw APIError.httpStatus(503)
        case .unauthorized: throw APIError.unauthorized
        case .unconfigured: throw APIError.notConfigured
        default: break
        }
    }
    func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage {
        try check()
        let rows: [TopicSummary]
        if scenario == .empty || pageNumber > 2 { rows = [] }
        else {
            let ids = pageNumber == 1 ? Array(7..<(7 + query.pageSize)) : [7 + query.pageSize]
            rows = try ids.map { id in
                try JSONDecoder().decode(TopicSummary.self, from: Data("{\"id\":\(id),\"name\":\"Sample route \(id)\",\"description\":\"Offline synthetic route\"}".utf8))
            }.filter { query.keyword == nil || $0.name.localizedCaseInsensitiveContains(query.keyword!) }
        }
        return TopicPage(rows: rows, pageNumber: pageNumber, pageSize: query.pageSize)
    }
    func topicDetail(id: Int) async throws -> TopicDetail {
        try check()
        if scenario == .unavailable { throw TopicReadFailure.unavailable }
        let json = TopicSyntheticFixtures.detailJSON
            .replacingOccurrences(of: "\"id\":7,", with: "\"id\":\(id),")
            .replacingOccurrences(of: "\"merchantClosed\":false", with: "\"merchantClosed\":\(scenario == .closed ? "true" : "false")")
        return try JSONDecoder().decode(TopicDetail.self, from: Data(json.utf8))
    }
}

@MainActor struct TopicFixtureHostView: View {
    @State private var reader: TopicFixtureReader
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-topic-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _reader = State(initialValue: TopicFixtureReader(scenario: raw.flatMap(TopicFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View {
        if reader.scenario == .unavailable {
            NavigationStack { TopicDetailView(id: 7, reader: reader) }
        } else { TopicBrowserView(reader: reader, pageSize: 2) }
    }
}
#endif
