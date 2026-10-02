import SwiftUI

@MainActor struct NativeRouteErrorView: View {
    let failure: NativeRouteFailure
    let goHome: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ContentUnavailableView {
            Label("nativeNav.error.title", systemImage: "questionmark.folder")
        } description: {
            Text(failure == .cannotOpen ? "nativeNav.error.cannotOpen" : "nativeNav.error.detail")
        } actions: {
            Button("nativeNav.close") { dismiss() }
            Button("homeFeed.title", action: goHome)
        }.navigationTitle("nativeNav.error.title").accessibilityIdentifier("nativeNav.error")
    }
}

@MainActor struct TeamInvitationEntryView: View {
    let makeCoordinator: () -> TeamCoordinator
    var onLogin: (() -> Void)? = nil
    var onOpen: ((TeamInvitationRoute) -> Void)? = nil
    @State private var code = ""
    @State private var route: TeamInvitationPresentation?
    @State private var invalid = false
    var body: some View {
        Form {
            Section("nativeNav.team.open") {
                TextField("nativeNav.team.code", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("nativeNav.team.code")
                Text("nativeNav.team.notice").font(.footnote)
                Button("nativeNav.open") {
                    guard let value = try? TeamInvitationRoute(code: code) else { invalid = true; return }
                    invalid = false
                    if let onOpen { onOpen(value) } else { route = TeamInvitationPresentation(route: value) }
                }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if invalid { Text("nativeNav.invalid").foregroundStyle(.secondary) }
            }
        }.navigationTitle("team.invitation")
            .navigationDestination(item: $route) { item in
                TeamInvitationDestination(route: item.route, makeCoordinator: makeCoordinator, onLogin: onLogin)
            }
            .privacySensitive()
    }
}
private struct TeamInvitationPresentation: Hashable {
    let id = UUID(); let route: TeamInvitationRoute
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
@MainActor private struct TeamInvitationDestination: View {
    let route: TeamInvitationRoute
    let makeCoordinator: () -> TeamCoordinator
    var onLogin: (() -> Void)?
    var body: some View {
        TeamDetailView(lookup: .invitation(route.code), coordinator: makeCoordinator())
            .toolbar { if let onLogin { Button("team.signIn", action: onLogin) } }
    }
}

/// Normal wall entry for a source /badge query link. HTTPS links still go through the
/// separate approved-origin router; this form accepts only the documented relative path.
@MainActor struct BadgeRouteEntryView: View {
    let reader: any ProfileReading
    var media: (any ObjectCardImageLoading)? = nil
    @State private var text = ""
    @State private var route: BadgeRoutePresentation?
    @State private var invalid = false
    @State private var scope = UUID()
    var body: some View {
        Form {
            TextField("nativeNav.badge.path", text: $text, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("nativeNav.badge.path")
            Text("nativeNav.badge.notice").font(.footnote)
            Button("nativeNav.open") {
                guard case .badge(let parameters) = NativeNavigationContract.parseInternal(text) else { invalid = true; return }
                invalid = false; route = BadgeRoutePresentation(parameters: parameters, scope: scope)
            }.disabled(text.isEmpty)
            if invalid { Text("nativeNav.invalid") }
        }.navigationTitle("nativeNav.badge.open")
            .sheet(item: $route) { target in
                NavigationStack {
                    ObjectBadgeRoutePreview(parameters: target.parameters, expectedScope: target.scope, currentScope: { scope }, media: media)
                        .toolbar { Button("nativeNav.close") { route = nil } }
                }
            }
            .onChange(of: reader.identity) { _, _ in scope = UUID(); route = nil; text = "" }
            .onDisappear { scope = UUID(); route = nil }
    }
}
private struct BadgeRoutePresentation: Identifiable {
    let id = UUID(); let parameters: ObjectBadgeDetailParameters; let scope: UUID
}
