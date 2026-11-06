import SwiftUI

@MainActor struct SessionTopicBrowserView:View {
    @EnvironmentObject private var session:AppSession
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        TopicBrowserView(reader:session.topicReader,onClose:{ dismiss() }, publicMerchant:session.publicMerchantHomeContext, makeAudio:session.platformConsumers.audioFactory, makeExternalMaps:session.platformConsumers.mapsFactory, selfPlayDestination: { AnyView(SessionTopicSelfPlayView(session: session, topic: $0)) })
            .environment(\.topicPricingDestination, session.publisherLifecycleContext.map { context -> (Int) -> AnyView in
                { topicID in AnyView(PublisherPricingView(topicID: topicID, client: context.client, coordinator: context.coordinator)) }
            })
            .id(session.topicReader.scope)
    }
}
