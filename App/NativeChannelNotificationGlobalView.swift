import SwiftUI

/// Presentation identity only. It carries no preference data or capability. The original
/// destination creates/revalidates its own scoped coordinator and protected journal.
struct NativeChannelNotificationGlobalNavigation {
    struct Route: Identifiable, Equatable {
        let id = UUID()
        let scope: NativeChannelNotificationScope
    }
    private(set) var selection: Route?
    mutating func open(_ scope: NativeChannelNotificationScope,
                       currentScopes: [NativeChannelNotificationScope], canOpen: Bool) {
        guard canOpen, selection == nil, currentScopes.contains(scope) else { return }
        selection = Route(scope: scope)
    }
    mutating func close(_ id: UUID?) {
        guard selection?.id == id else { return }
        selection = nil
    }
}

@MainActor struct NativeChannelNotificationGlobalView: View {
    @Environment(\.locale) private var locale
    @Environment(\.themeDomain) private var domain
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    @Bindable var model: NativeChannelNotificationCoordinator
    let permission: NativeNotificationPermissionState
    let makeConversation: (NativeChannelNotificationScope) -> NativeChannelNotificationCoordinator?
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = NativeChannelNotificationGlobalNavigation()
    @State private var visible = false
    @State private var screenGeneration: UInt64 = 0
    @State private var screenTask: Task<Void, Never>?
    var body: some View {
        let ticket = screenGeneration
        Form {
            NativeChannelNotificationStatusSection(model: model, perform: { perform($0, expected: ticket) })
            Section { NativeChannelUnreadSummaryContent(model: model) }
            Section {
                NavigationLink { NativeNotificationPermissionNudgeView(model: permission) } label: {
                    Label(permission.snapshot.map { NativeChannelNotificationPresentation.authorization($0.authorization, locale: locale) } ?? n("permission.waiting"), systemImage: "bell.badge")
                }.accessibilityIdentifier("notification.global.permission")
            }
            if let directory = model.directory {
                Section {
                    LabeledContent(n("global.serverFallback"), value: NativeChannelNotificationPresentation.level(directory.defaults.effectiveLevel, locale: locale))
                    if let scope = model.accountDefaultScope {
                        Button { open(scope, expected: ticket) } label: { Text(n("global.accountDefault")) }
                            .accessibilityIdentifier("notification.global.defaults")
                    } else {
                        Text(n("global.missingDefaults"))
                    }
                } header: { Text(n("global.defaultLevel")) }
                Section {
                    let overrides = directory.list.filter { !$0.scope.isAccountDefault }
                    if overrides.isEmpty { Text(n("global.noOverrides")) }
                    ForEach(overrides) { row in
                        Button { open(row.scope, expected: ticket) } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                                Text(NativeChannelNotificationPresentation.format(row.scope.type == 1 ? "notification.global.channelScope" : "notification.global.clubScope", locale: locale, row.scope.value))
                                Text(NativeChannelNotificationPresentation.format("notification.global.rowSummary", locale: locale, NativeChannelNotificationPresentation.level(row.level, locale: locale), NativeChannelNotificationPresentation.effective(row, locale: locale)))
                                    .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: { Text(n("global.savedOverrides")) } footer: { Text(n("global.overrideBoundary")) }
            }
            Section { Button(n("global.refresh")) {
                perform({ await $0.refresh() }, expected: ticket)
            }.disabled(model.isBusy || screenTask != nil) }
        }
        .nativeChannelScreen()
        .font(Theme.Font.body)
        .tint(Theme.Color.accent(in: domain))
        .navigationTitle(NativeChannelNotificationPresentation.localized("notification.global.title", locale: locale))
        .accessibilityIdentifier("notification.global.screen")
        // Outside directory/ForEach: parent deactivation must still purge rows, but must
        // not remove the presentation that owns the original child settings flow.
        .navigationDestination(isPresented: destinationBinding) {
            if let route = navigation.selection {
                NativeChannelNotificationDestination(scope: route.scope, permission: permission, makeFlow: makeConversation)
                    .id(route.id)
            }
        }
        .onAppear { visible = true; reopen() }
        .onDisappear { visible = false; suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reopen() } else { suspend() }
        }
    }
    private var destinationBinding: Binding<Bool> {
        let captured = navigation.selection?.id
        return Binding(get: { navigation.selection != nil }, set: { presented in
            if !presented { navigation.close(captured) }
        })
    }
    private func open(_ scope: NativeChannelNotificationScope, expected: UInt64) {
        var scopes = model.directory?.list.filter { !$0.scope.isAccountDefault }.map(\.scope) ?? []
        if let accountDefault = model.accountDefaultScope { scopes.append(accountDefault) }
        navigation.open(scope, currentScopes: scopes,
            canOpen: owns(expected) && screenTask == nil && model.isCurrent && !model.isBusy)
    }
    private func suspend() {
        screenGeneration &+= 1
        screenTask?.cancel(); screenTask = nil
        model.deactivate()
    }
    private func reopen() {
        suspend()
        guard visible, scenePhase == .active else { return }
        start { await $0.activate() }
    }
    private func perform(_ operation: @escaping NativeChannelNotificationScreenOperation, expected: UInt64) {
        guard owns(expected), screenTask == nil, model.isCurrent else { return }
        start(operation)
    }
    private func start(_ operation: @escaping NativeChannelNotificationScreenOperation) {
        screenGeneration &+= 1
        let ticket = screenGeneration
        screenTask = Task { @MainActor in
            guard !Task.isCancelled, owns(ticket) else { return }
            await operation(model)
            guard !Task.isCancelled, owns(ticket) else { return }
            await permission.refresh()
            guard !Task.isCancelled, owns(ticket) else { return }
            screenTask = nil
        }
    }
    private func owns(_ ticket: UInt64) -> Bool {
        visible && scenePhase == .active && screenGeneration == ticket
    }
}
