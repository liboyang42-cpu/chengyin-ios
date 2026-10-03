import SwiftUI

/// Session owner invalidates all active consumers BEFORE credentials/account are replaced.
/// No production factory supplies native drivers. Injection is explicit and optional.
@MainActor final class PlatformConsumerSessionOwner {
    private(set) var scope = UUID()
    private let audioBuilder: (() -> PlatformAudioPlayback)?
    private let mapsBuilder: (() -> PlatformExternalMaps)?
    private var audio: [PlatformAudioPlayback] = []
    private var maps: [PlatformExternalMaps] = []
    init(audio: (() -> PlatformAudioPlayback)? = nil, maps: (() -> PlatformExternalMaps)? = nil) {
        audioBuilder = audio; mapsBuilder = maps
    }
    var audioFactory: (() -> PlatformAudioPlayback)? {
        guard let audioBuilder else { return nil }
        return { [self] in let model = audioBuilder(); audio.append(model); return model }
    }
    var mapsFactory: (() -> PlatformExternalMaps)? {
        guard let mapsBuilder else { return nil }
        return { [self] in let model = mapsBuilder(); maps.append(model); return model }
    }
    func invalidate() {
        audio.forEach { $0.dispose() }; maps.forEach { $0.invalidate() }
        audio.removeAll(); maps.removeAll(); scope = UUID()
    }
}

/// Default read/write denial has no HTTP implementation and cannot reach a backend.
struct CommunityDormantHTTPTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) { throw APIError.notConfigured }
}

@MainActor struct SessionTopicDetailView: View {
    let id: Int
    @ObservedObject var session: AppSession
    var body: some View {
        Group {
            if session.account == nil {
                TopicIssueView(issue: .unauthorized).accessibilityIdentifier("topic.detail.signIn")
            } else {
                TopicDetailView(id: id, reader: session.topicReader,
                    activityDestination: { AnyView(ActivityDetailView(id: $0, reader: session)) },
                    publicMerchant: session.publicMerchantHomeContext,
                    makeAudio: session.platformConsumers.audioFactory, makeExternalMaps: session.platformConsumers.mapsFactory,
                    publisherDestination: { detail in
                        guard detail.isOwner, let resource = try? PublishedResource(kind: .topic, value: detail.id) else { return AnyView(EmptyView()) }
                        return AnyView(PublisherLifecycleNavigationLink(session: session, resource: resource))
                    }, reviewOwner: session.contextualReviews?.coordinator(.topic(id)), selfPlayDestination: { AnyView(SessionTopicSelfPlayView(session: session, topic: $0)) })
                    .id(session.contentDetailRevision)
            }
        }
    }
}

#if DEBUG
@MainActor struct ClubCommunityFixtureRoot: View {
    private let context = try? ClubCommunityFixture.context()
    var body: some View {
        NavigationStack {
            if let context { ClubCommunityFeedView(context: context, identity: ClubCommunityFixture.identity, clubID: 10) }
            else { Text("club.community.loadError") }
        }
    }
}
#endif
