import SwiftUI

@MainActor struct SessionTopicBrowserView:View {
    @EnvironmentObject private var session:AppSession
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        TopicBrowserView(reader:session.topicReader,onClose:{ dismiss() }, publicMerchant:session.publicMerchantHomeContext, makeAudio:session.platformConsumers.audioFactory, makeExternalMaps:session.platformConsumers.mapsFactory)
            .id(session.topicReader.scope)
    }
}
