import SwiftUI

@MainActor struct ClubMemberWelcomeHost: View {
    let club: ClubRecord
    let identity: ClubReadIdentity
    let namespace: String?
    let role: String?
    let active: Bool
    let goEvents: () -> Void
    @StateObject private var flow = ClubWelcomePresentation()
    @Environment(\.scenePhase) private var scenePhase
    private var current: Bool { active && scenePhase == .active && identity.isSignedIn && club.isJoined && !club.isOwner && !club.viewerIdentityUnavailable }
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { consider() }
            .onChange(of: club) { _, _ in consider() }
            .onChange(of: identity) { _, _ in flow.clear(); consider() }
            .onChange(of: namespace) { _, _ in flow.clear(); consider() }
            .onChange(of: role) { _, _ in consider() }
            .onChange(of: current) { _, _ in consider() }
            .onDisappear { flow.clear() }
            .sheet(item: Binding(get: { current ? flow.presentation : nil }, set: { value in if value == nil { flow.clear() } })) { original in
                ClubMemberWelcomeLiveSheet(flow: flow, originalID: original.id, close: { flow.dismiss(original.id) }, goEvents: {
                    guard current, flow.presentation?.id == original.id, original.identity == identity,
                          original.club.id == club.id, original.namespace == namespace else { return }
                    flow.dismiss(original.id); goEvents()
                })
            }
    }
    private func consider() { flow.consider(club: club, identity: identity, namespace: namespace, role: role, active: current) }
}
@MainActor private struct ClubMemberWelcomeLiveSheet: View {
    @ObservedObject var flow: ClubWelcomePresentation
    let originalID: UUID
    let close: () -> Void
    let goEvents: () -> Void
    var body: some View {
        if let current = flow.presentation, current.id == originalID {
            ClubMemberWelcomeSheet(value: current, close: close, goEvents: goEvents)
        }
    }
}
@MainActor struct ClubMemberWelcomeSheet: View {
    let value: ClubMemberWelcome
    let close: () -> Void
    let goEvents: () -> Void
    @Environment(\.themeDomain) private var domain
    var body: some View {
        NavigationStack {
            List {
                if let note = value.club.welcomeNote, !note.isEmpty {
                    Section { Text(verbatim: note).textSelection(.enabled) } header: { Text("welcome.note", tableName: "ClubMemberWelcome") }
                }
                Section {
                    Label { Text(LocalizedStringKey(value.postingKey), tableName: "ClubMemberWelcome") } icon: { Image(systemName: "text.bubble") }
                    Label { Text(LocalizedStringKey(value.eventsKey), tableName: "ClubMemberWelcome") } icon: { Image(systemName: "calendar") }
                    Label { Text("welcome.overview", tableName: "ClubMemberWelcome") } icon: { Image(systemName: "person.3") }
                } header: { Text("welcome.actions", tableName: "ClubMemberWelcome") }
                Section {
                    Button(action: close) { Text("welcome.gotIt", tableName: "ClubMemberWelcome") }.accessibilityIdentifier("club.welcome.close")
                        .buttonStyle(.bordered)
                    Button(action: goEvents) { Text("welcome.events", tableName: "ClubMemberWelcome") }.accessibilityIdentifier("club.welcome.events")
                        .buttonStyle(.borderedProminent)
                }
            }
            .font(Theme.Font.body)
            .listStyle(.insetGrouped)
            .scrollContentBackground(Theme.Generated.color("--cy-color-bg-page", in: domain) != nil ? .hidden : .automatic)
            .background {
                if let background = Theme.Generated.color("--cy-color-bg-page", in: domain) { background }
            }
            .navigationTitle(Text("welcome.title", tableName: "ClubMemberWelcome"))
            .safeAreaInset(edge: .top) { if !value.club.name.isEmpty { Text(verbatim: value.club.name).font(.headline).padding(.horizontal) } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(action: close) { Text("welcome.close", tableName: "ClubMemberWelcome") } } }
        }
    }
}
