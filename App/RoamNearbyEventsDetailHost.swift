import SwiftUI
import Combine

/// Reuses the real detail readers and screens without passing AppSession or any writer to them.
/// The entry card keeps its existing topic-first route; a map activity keeps its activity ID.
@MainActor struct RoamNearbyEventsDetailHost: View {
    let target: RoamEventDestination
    @ObservedObject var session: AppSession
    var body: some View {
        Group {
            if session.account == nil {
                TopicIssueView(issue: .unauthorized)
            } else if let message = session.contentDetailReadAvailability.messageKey {
                ContentUnavailableView("roam.detail", systemImage: "network.slash",
                    description: Text(LocalizedStringKey(message)))
            } else {
                switch target {
                case .activity(let id):
                    RoamNearbyEventsActivityDetail(id: id, base: session)
                        .id(session.activityPresentationIdentity)
                case .topic(let id):
                    RoamNearbyEventsTopicDetail(id: id, base: session.topicReader)
                        .id(session.topicReader.scope)
                }
            }
        }
        .accessibilityIdentifier("roam.nearbyEvent.readOnlyDetail")
    }
}

@MainActor private struct RoamNearbyEventsActivityDetail: View {
    @State private var reader: RoamNearbyEventsActivityReader
    private let id: Int
    init(id: Int, base: any ActivityReading) {
        self.id = id; _reader = State(initialValue: .init(id: id, base: base))
    }
    var body: some View {
        ActivityDetailView(id: id, reader: reader, registrationEnabled: false)
    }
}

@MainActor private struct RoamNearbyEventsTopicDetail: View {
    @State private var reader: RoamNearbyEventsTopicReader
    private let id: Int
    init(id: Int, base: any TopicReading) {
        self.id = id; _reader = State(initialValue: .init(id: id, base: base))
    }
    var body: some View {
        // No registration/activity destination, self-play, review writer, publisher or payment host.
        TopicDetailView(id: id, reader: reader)
            .environment(\.topicPricingDestination, nil)
    }
}

/// Exact-target facade intentionally cannot be downcast to AppSession by ActivityDetailView.
@MainActor final class RoamNearbyEventsActivityReader: ActivityReading {
    private let id: Int
    private let base: any ActivityReading
    private let origin: String
    init(id: Int, base: any ActivityReading) {
        self.id = id; self.base = base; origin = base.activityPresentationIdentity
    }
    var isConfigured: Bool { id > 0 && base.isConfigured && base.activityPresentationIdentity == origin }
    var activityListIsConfigured: Bool { false }
    var activityPresentationIdentity: String { base.activityPresentationIdentity }
    var activityPresentationChanges: AnyPublisher<Void, Never> { base.activityPresentationChanges }
    func activities(page: Int, keyword: String) async throws -> [ActivitySummary] { throw APIError.notConfigured }
    func activityDetail(id: Int) async throws -> ActivityDetailAccess {
        guard id == self.id, id > 0 else { throw APIError.invalidRequest }
        guard isConfigured else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let result = try await base.activityDetail(id: id)
            guard !Task.isCancelled, isConfigured else { throw CancellationError() }
            if case .allowed(let detail) = result, detail.summary.id != id { throw APIError.malformedResponse }
            return result
        } catch {
            guard !Task.isCancelled, isConfigured else { throw CancellationError() }
            throw error
        }
    }
}

@MainActor final class RoamNearbyEventsTopicReader: TopicReading {
    private let id: Int
    private let base: any TopicReading
    private let origin: UUID
    init(id: Int, base: any TopicReading) { self.id = id; self.base = base; origin = base.scope }
    var isConfigured: Bool { id > 0 && base.isConfigured && base.scope == origin }
    var isOfflineExample: Bool { base.isOfflineExample }
    var scope: UUID { base.scope }
    func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage { throw APIError.notConfigured }
    func topicDetail(id: Int) async throws -> TopicDetail {
        guard id == self.id, id > 0 else { throw APIError.invalidRequest }
        guard isConfigured else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let result = try await base.topicDetail(id: id)
            guard !Task.isCancelled, isConfigured else { throw CancellationError() }
            guard result.id == id else { throw APIError.malformedResponse }
            return result
        } catch {
            guard !Task.isCancelled, isConfigured else { throw CancellationError() }
            throw error
        }
    }
}
