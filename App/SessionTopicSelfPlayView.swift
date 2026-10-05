import SwiftUI

@MainActor struct SessionTopicSelfPlayView: View {
    @ObservedObject var session: AppSession
    let topic: TopicDetail
    var body: some View {
        if let flow = session.topicSelfPlayFlow(topic: topic) {
            TopicSelfPlaySheet(flow: flow,
                orders: { AnyView(ProfileOrdersView(reader: session.profileReader, lifecycleCoordinator: session.orderLifecycleCoordinator)) },
                tickets: { AnyView(TicketWalletView(reader: session.ticketWalletReader, orderLifecycleCoordinator: session.orderLifecycleCoordinator)) })
                .id(session.sessionRevision)
        } else { TopicSelfPlayUnavailableSheet(topic: topic) }
    }
}
