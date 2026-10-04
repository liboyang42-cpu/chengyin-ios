import SwiftUI

@MainActor private final class ClubChatViewModel: ObservableObject {
    @Published var phase: ClubChatPhase = .idle
    let owner: ClubChatCoordinator
    init(_ owner: ClubChatCoordinator) { self.owner = owner }
    func observe() { owner.onChange = { [weak self] in self?.phase = self?.owner.visiblePhase ?? .stale }; phase = owner.visiblePhase }
}
@MainActor struct SessionClubChatView: View {
    let clubID: Int
    @ObservedObject var session: AppSession
    var body: some View {
        Group {
            if let owner = session.clubChatCoordinator(clubID: clubID) { ClubChatEntryView(owner: owner, session: session) }
            else { ContentUnavailableView("club.chat.title", systemImage: "person.3", description: Text("club.chat.disabled")) }
        }.navigationTitle(Text("club.chat.title"))
    }
}
@MainActor private struct ClubChatEntryView: View {
    @StateObject private var model: ClubChatViewModel
    @ObservedObject var session: AppSession
    @State private var conversation: MessagingConversation?
    init(owner: ClubChatCoordinator, session: AppSession) { _model = StateObject(wrappedValue: ClubChatViewModel(owner)); self.session = session }
    var body: some View {
        Form {
            Section {
                Text("club.chat.explanation")
                if !model.owner.service.isConfigured { Text("club.chat.disabled").accessibilityIdentifier("club.chat.disabled") }
                Button(model.phase == .unknown ? "club.chat.retry" : "club.chat.enter") {
                    Task { await model.owner.enter(); if case .ready(let row) = model.owner.visiblePhase { conversation = row } }
                }.disabled(!model.owner.canEnter).accessibilityIdentifier("club.chat.enter")
            }
            Section {
                switch model.phase {
                case .entering: ProgressView("club.chat.loading")
                case .unknown: Text("club.chat.unknown").accessibilityIdentifier("club.chat.unknown")
                case .rejected: Text("club.chat.rejected")
                case .stale: Text("poll.stale")
                default: EmptyView()
                }
            }
        }.privacySensitive().accessibilityIdentifier("club.chat.screen")
        .onAppear { model.observe() }
        .onDisappear { model.owner.suspend() }
        .onChange(of: model.owner.isCurrent) { _, current in if !current { conversation = nil } }
        .navigationDestination(isPresented: Binding(get: { conversation != nil && model.owner.isCurrent }, set: { if !$0 { conversation = nil } })) {
            if let conversation, model.owner.isCurrent {
                MessagingHistoryView(conversationID: conversation.id, conversation: conversation, reader: session.messagingReader,
                    sender: session.messageSender(for: conversation.id), mediaReader: session.socialMessageMediaReader, expanded: session.imExpandedNavigation).id(session.messagingViewIdentity)
            }
        }
    }
}
