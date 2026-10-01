#if DEBUG
import SwiftUI

/// Explicit, opt-in simulator/UI-test data. No account, service, URL or credential is created.
enum ActivityFixtureScenario: String {
    case tickets
    case clubGate = "club-gate"
    case retry
    case pagination

    static func selected(arguments: [String]) -> Self? {
        guard let flag=arguments.firstIndex(of:"--uitesting-activity-fixture"),
              arguments.indices.contains(flag+1) else { return nil }
        return Self(rawValue:arguments[flag+1])
    }
}

@MainActor
struct ActivityFixtureRootView: View {
    @State private var reader: ActivityFixtureReader

    init(scenario: ActivityFixtureScenario) {
        _reader=State(initialValue:ActivityFixtureReader(scenario:scenario))
    }

    var body: some View {
        VStack(spacing:0) {
            Text("activity.fixtureNotice")
                .font(.caption.bold())
                .padding(8)
                .frame(maxWidth:.infinity)
                .background(.yellow.opacity(0.2))
                .accessibilityIdentifier("activity.fixture.notice")
            ActivityBrowserView(reader:reader)
        }
    }
}

@MainActor
private final class ActivityFixtureReader: ActivityReading {
    let isConfigured=true
    private let scenario: ActivityFixtureScenario
    private var didFailList=false
    private var didFailDetail=false

    init(scenario: ActivityFixtureScenario) { self.scenario=scenario }

    func activities(page: Int, keyword: String) async throws -> [ActivitySummary] {
        try Task.checkCancellation()
        guard page > 0 else { throw APIError.invalidRequest }
        if scenario == .retry, !didFailList {
            didFailList=true
            throw APIError.httpStatus(503)
        }
        // Any submitted search intentionally has no matches in these small fixtures.
        guard keyword.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return [] }
        if scenario == .pagination {
            let ids: [Int]
            switch page {
            case 1: ids=Array(601...610)
            case 2: ids=[611]
            default: ids=[]
            }
            return try ids.map { try summary(id:$0,name:"Fixture activity \($0)") }
        }
        guard page == 1 else { return [] }
        return [try summary(id:101,name:scenario == .clubGate ? "Fixture club activity" : "Fixture ticket activity")]
    }

    func activityDetail(id: Int) async throws -> ActivityDetailAccess {
        try Task.checkCancellation()
        guard id == 101 || (scenario == .pagination && (601...611).contains(id)) else {
            throw APIError.invalidRequest
        }
        if scenario == .clubGate { return .clubRequired(clubID:201,message:nil) }
        if scenario == .retry, !didFailDetail {
            didFailDetail=true
            throw APIError.httpStatus(503)
        }
        // Intentionally omit image URLs and coordinates: no Map or remote media is instantiated.
        let data=Data("""
        {
          "id": \(id), "name": "Fixture ticket activity", "minAmout": null,
          "omsTicketList": [
            {"id": 501, "name": "Fixture unknown ticket", "price": null, "remainingInventory": null},
            {"id": 502, "name": "Fixture sold-out ticket", "price": 12.5, "remainingInventory": 0}
          ]
        }
        """.utf8)
        return .allowed(try JSONDecoder().decode(ActivityDetail.self,from:data))
    }

    private func summary(id: Int, name: String) throws -> ActivitySummary {
        let data=try JSONSerialization.data(withJSONObject:["id":id,"name":name])
        return try JSONDecoder().decode(ActivitySummary.self,from:data)
    }
}
#endif
