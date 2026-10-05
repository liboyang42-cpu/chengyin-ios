#if DEBUG
import SwiftUI

@MainActor final class TopicFixtureReader: TopicReading {
    enum Scenario: String { case content, empty, failure, unauthorized, unconfigured, unavailable, closed, itinerary, reviews, reviewsEmpty, reviewsUnknown }
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
        if [.reviews, .reviewsEmpty, .reviewsUnknown].contains(scenario) {
            let fields: String
            switch scenario {
            case .reviews where id == 7:
                fields = #", "averageRating":4.2,"commentCount":12,"commentList":[{"memberNickname":"Example walker","createTime":"2030-01-02 10:00","rating":4,"contents":"A useful route review."},{"rating":0}]"#
            case .reviews:
                fields = #", "averageRating":3,"commentCount":3,"commentList":[{"memberNickname":"Another walker","rating":3,"contents":"A different route review."}]"#
            case .reviewsEmpty:
                fields = #", "averageRating":0,"commentCount":0,"commentList":[]"#
            default:
                fields = #", "averageRating":null,"commentCount":null,"commentList":null"#
            }
            let json = "{\"id\":\(id),\"name\":\"Synthetic review route\"\(fields)}"
            return try JSONDecoder().decode(TopicDetail.self, from: Data(json.utf8))
        }
        if scenario == .itinerary {
            // Fictional geometry only; no device location or routed directions.
            let json = #"""
            {"id":7,"name":"Synthetic itinerary","storyLocked":true,"totalChapterCount":4,"chaptersList":[
              {"id":11,"title":"Adjacent stops","nodes":[
                {"id":21,"name":"First example stop","latitude":1,"longitude":1},
                {"id":22,"name":"Second example stop","latitude":"1.001","longitude":"1","nodeTime":240},
                {"id":23,"name":"Unknown location stop"},
                {"id":24,"name":"Last example stop","latitude":1.003,"longitude":1}]},
              {"id":12,"title":"Separate chapter","nodes":[
                {"id":25,"name":"New chapter first stop","latitude":1.005,"longitude":1}]},
              {"id":13,"title":"Empty chapter","nodes":[]} ]}
            """#
            return try JSONDecoder().decode(TopicDetail.self, from: Data(json.utf8))
        }
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
        if reader.scenario == .unavailable || reader.scenario == .itinerary {
            NavigationStack { TopicDetailView(id: 7, reader: reader) }
        } else { TopicBrowserView(reader: reader, pageSize: 2) }
    }
}
#endif
