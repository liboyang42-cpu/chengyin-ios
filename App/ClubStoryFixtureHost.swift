#if DEBUG
import SwiftUI

/// Synthetic P057 route/play fixtures. No AppSession, API grants or image origins.
@MainActor struct ClubStoryFixtureHost: View {
    @StateObject private var store = ClubStoryFixtureStore()
    var body: some View {
        NavigationStack {
            ClubGovernanceReadView(operation: .topicOverview, scope: ClubStoryFixtureData.scope,
                identity: store.identity, access: store.access, coordinator: store.coordinator)
                .environment(\.clubStoryTemplates, store.templates)
        }
        .safeAreaInset(edge: .bottom) {
            ScrollView(.horizontal) {
                HStack {
                    Button("Refresh source") { store.refreshSource() }.accessibilityIdentifier("club.story.fixture.refresh")
                    Button("Switch account") { store.switchAccount() }.accessibilityIdentifier("club.story.fixture.account")
                    Button("Replace reader") { store.replaceReader() }.accessibilityIdentifier("club.story.fixture.reader")
                    Button("Finish detail") { store.member.finish() }.accessibilityIdentifier("club.story.fixture.finish")
                }.padding(8)
            }.background(.regularMaterial)
        }
    }
}

@MainActor final class ClubStoryFixtureStore: ObservableObject {
    let access = ClubGovernanceFixtureAccess()
    lazy var coordinator = ClubGovernanceCoordinator(access: access)
    @Published var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    @Published var revision: UInt64 = 0
    var member = ClubStoryFixtureMemberReader()
    private let scenario: String
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--club-story-scenario"), arguments.indices.contains(index + 1) { scenario = arguments[index + 1] }
        else { scenario = "ready" }
        access.overrideValue[.topicOverview] = ClubStoryFixtureData.value(scenario: scenario)
        member.isConfigured = scenario != "unavailable"
        member.delayed = scenario == "delayed"
    }
    var templates: ClubStoryTemplateContext {
        let captured = member
        return .init(viewerRevision: revision, reader: captured, destination: { id in
            AnyView(MemberTemplateDetailView(id: id, reader: captured))
        })
    }
    func refreshSource() {
        access.overrideValue[.topicOverview] = ClubStoryFixtureData.value(scenario: "refreshed")
        revision &+= 1
    }
    func switchAccount() {
        member.isAuthenticated = false; member.scope = UUID()
        let next = ClubReadIdentity(accountID: 799, epoch: (identity?.epoch ?? 0) + 1)
        access.identity = next; access.readFailure = .forbidden; identity = next; revision &+= 1
    }
    func replaceReader() { member.scope = UUID(); member = ClubStoryFixtureMemberReader(); revision &+= 1 }
}
@MainActor final class ClubStoryFixtureMemberReader: MemberTemplateReading {
    var scope = UUID(), isAuthenticated = true, isConfigured = true, delayed = false
    var requests: [Int] = []
    private var pending: (MemberPlayTemplateID, CheckedContinuation<MemberTemplateDetail, Error>)?
    func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        guard isAuthenticated else { throw APIError.unauthorized }
        guard isConfigured else { throw APIError.notConfigured }
        requests.append(id.rawValue)
        if delayed { return try await withCheckedThrowingContinuation { pending = (id, $0) } }
        return try result(id)
    }
    func finish() {
        guard let (id, continuation) = pending else { return }
        pending = nil; continuation.resume(with: Result { try result(id) })
    }
    private func result(_ id: MemberPlayTemplateID) throws -> MemberTemplateDetail {
        let bytes = try JSONSerialization.data(withJSONObject: ["id": id.rawValue,
            "title": "Synthetic personal template \(id.rawValue)", "description": "Exact personal-template destination", "validationMethod": 1])
        return try JSONDecoder().decode(MemberTemplateDetail.self, from: bytes)
    }
}
enum ClubStoryFixtureData {
    static let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
    static func value(scenario: String = "ready") -> ClubGovernanceValue {
        if scenario == "empty" { return ClubGovernanceFixtures.json(#"{"id":91,"chaptersList":[]}"#) }
        var value = ClubGovernanceFixtures.json(#"{"id":91,"name":"Synthetic club story","chaptersList":[{"id":151,"name":"First chapter","description":"Follow the lanterns through the courtyard. This synthetic chapter has a longer story to exercise expansion and independent chapter selection. The second chapter has another story and a different play. No walk-time estimate is provided.","totalTime":90,"nodes":[{"id":141,"name":"Lantern courtyard","businessTime":"09:00–18:00","address":"Synthetic courtyard address","cmsMemberTemplate":{"id":142,"title":"Lantern puzzle","validationMethod":1,"players":"2–6 players","duration":15,"difficulty":"2"}},{"id":143,"name":"Garden arch","businessTime":"10:00–17:00","address":"Synthetic garden address","cmsMemberTemplate":{"id":144,"title":"Garden photo","validationMethod":2,"duration":10}}]},{"id":152,"name":"Second chapter","description":"A separate synthetic chapter story.","nodes":[{"id":145,"name":"Old library","address":"Synthetic library address","cmsMemberTemplate":{"id":146,"title":"Library choices","validationMethod":3,"players":"1–4 players"}}]},{"id":153,"name":"Awaiting merchants","nodes":[]}]}"#).object ?? [:]
        if scenario == "refreshed" { value["chaptersList"] = .array([]) }
        if scenario == "duplicateChapter", var chapters = value["chaptersList"]?.array, var chapter = chapters[1].object {
            chapter["id"] = .integer(151); chapters[1] = .object(chapter); value["chaptersList"] = .array(chapters)
        }
        if scenario == "invalid", var chapters = value["chaptersList"]?.array, var chapter = chapters[0].object,
           var nodes = chapter["nodes"]?.array, var node = nodes[0].object, var template = node["cmsMemberTemplate"]?.object {
            template["id"] = .integer(0); node["cmsMemberTemplate"] = .object(template); nodes[0] = .object(node)
            chapter["nodes"] = .array(nodes); chapters[0] = .object(chapter); value["chaptersList"] = .array(chapters)
        }
        return .object(value)
    }
}
#endif
