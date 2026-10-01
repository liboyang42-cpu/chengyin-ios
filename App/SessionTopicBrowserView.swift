import SwiftUI

@MainActor struct SessionTopicBrowserView:View {
    @EnvironmentObject private var session:AppSession
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        TopicBrowserView(reader:session.topicReader,onClose:{ dismiss() })
            .id(session.topicReader.scope)
    }
}
