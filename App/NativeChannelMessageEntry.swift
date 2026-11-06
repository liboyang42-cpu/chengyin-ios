import SwiftUI

/// Wrap the EXISTING normal channel history/composer. It never creates a conversation,
/// send client, grant, URLSession or an independent message list.
@MainActor struct NativeChannelMessageEntry<Content: View>: View {
    @State var coordinator: NativeChannelMessageCoordinator
    @ViewBuilder let originalContent: () -> Content
    var locateOriginalMessage: ((NativeChannelMessageID) -> Void)?
    /// Extra host actions; with any present, pins join them in the … menu.
    var moreActions: AnyView? = nil
    @State private var showingPins = false
    @State private var showingSearch = false
    @State private var pendingLocation:NativeChannelMessageID?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: Theme.Space.s2) {
            if coordinator.isCurrent && coordinator.client.allows(.mutations) {
                // ConversationHost filters payloads with canDisplay until the same-response
                // metadata is ready; keep the ORIGINAL failed-read recovery controls reachable.
                if !coordinator.historyReady {
                    ProgressView { Text("source.required", tableName: "NativeChannelMessage") }
                        .font(.footnote).padding(.horizontal, Theme.Space.pageX)
                }
                originalContent()
            }
            else if !coordinator.isCurrent {
                // Not yet activated (first frame) or retired while backgrounded.
                ProgressView { Text("source.required", tableName: "NativeChannelMessage") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                ContentUnavailableView { Label("d7.channelChat.unavailable", systemImage: "bubble.left") }
                    .frame(maxHeight: .infinity)
            }
            NativeChannelMessageRecoveryView(coordinator: coordinator)
        }
        .toolbar {
            // At most two actions: search, then pins (or a … menu once the host adds more).
            ToolbarItemGroup(placement: .topBarTrailing) {
                if coordinator.isCurrent && coordinator.client.allows(.search) {
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel(Text("search.title", tableName: "NativeChannelMessage"))
                }
                let showsPins = coordinator.isCurrent && coordinator.client.allows(.pins)
                if let moreActions {
                    Menu {
                        if showsPins {
                            Button { showingPins = true } label: { Label { Text("pins.title", tableName: "NativeChannelMessage") } icon: { Image(systemName: "pin") } }
                        }
                        moreActions
                    } label: { Label("im.chat.more", systemImage: "ellipsis") }
                } else if showsPins {
                    Button { showingPins = true } label: { Image(systemName: "pin") }
                        .accessibilityLabel(Text("pins.title", tableName: "NativeChannelMessage"))
                }
            }
        }
        .sheet(isPresented: $showingPins,onDismiss:finishLocation) {
            NavigationStack { NativeChannelMessagePinsView(coordinator: coordinator, locateOriginal: {pendingLocation=$0;showingPins=false}) }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSearch,onDismiss:finishLocation) {
            NavigationStack { NativeChannelMessageSearchView(model: coordinator.search, locateOriginal: {pendingLocation=$0;showingSearch=false}) }
                .presentationDragIndicator(.visible)
        }
        .task { await coordinator.activate() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if coordinator.isCurrent && coordinator.historyReady {
                    do { try await coordinator.synchronizeMutations() }
                    catch { if !coordinator.client.allows(.mutations) { coordinator.retire(); return } }
                }
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await coordinator.activate() } } else { coordinator.retire() }
        }
        .onChange(of: coordinator.client.identity) { _, _ in coordinator.retire() }
        // Navigation to the original message detail keeps its current source visible.
        // View-task cancellation stops foreground polling; scene/identity changes retire dispatches.
        .onDisappear { coordinator.search.retire(); coordinator.pins.retire() }
        .nativeChannelScreen()
        .privacySensitive()
    }
    private func finishLocation(){guard let id=pendingLocation else{return};pendingLocation=nil;if coordinator.isCurrent{locateOriginalMessage?(id)}}
}

@MainActor struct NativeChannelMessageRecoveryView: View {
    @Environment(\.locale) private var locale
    private var copy: NativeChannelPinLocalization { .init(locale: locale) }
    @Environment(\.themeDomain) private var domain
    @Bindable var coordinator: NativeChannelMessageCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            switch coordinator.state {
            case .saving, .dispatching, .checking: ProgressView()
            case .unknown:
                Text("request.unknown", tableName: "NativeChannelMessage").nativeChannelNotice(systemImage: "clock")
                Button { Task { await coordinator.recover() } } label: { Text("request.lookup", tableName: "NativeChannelMessage") }
            case .rejected(let code):
                Text("request.rejected", tableName: "NativeChannelMessage")
                if let message = coordinator.lastFailure?.message, !message.isEmpty { Text(verbatim: message).font(.footnote).foregroundStyle(.secondary) }
                if code == "MESSAGE_VERSION_CONFLICT" { Text("message.changed", tableName: "NativeChannelMessage").font(.footnote).foregroundStyle(.secondary) }
                Button { coordinator.acknowledgeRejected() } label: { Text("request.keepDraft", tableName: "NativeChannelMessage") }
            case .persistenceFailed: Text("request.storage", tableName: "NativeChannelMessage")
            case .applied: Text("d7.channelChat.changeSaved")
            case .accessClosed: Text("access.closed", tableName: "NativeChannelMessage")
            case .idle: EmptyView()
            }
            if coordinator.isCurrent, let pending = coordinator.original,
               pending.operation == .pin || pending.operation == .unpin {
                Label { Text(verbatim: copy.format("p23.pending", copy.operation(pending.operation))) } icon: { Image(systemName: "clock") }
                    .fixedSize(horizontal: false, vertical: true)
            }
            if coordinator.isCurrent, coordinator.original == nil, let readback = coordinator.pins.appliedReadback {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: copy.format("p23.applied", copy.operation(readback.operation)))
                    Group {
                        switch readback.state {
                        case .reading: Text(copy.text("p23.current.reading"))
                        case .matches: Text(copy.text("p23.current.matches"))
                        case .differs: Text(copy.text("p23.current.differs"))
                        case .failed: Text(copy.text("p23.current.failed"))
                        }
                    }.font(.footnote).foregroundStyle(.secondary)
                    Button(copy.text("p23.current.refresh")) { Task { await coordinator.pins.refreshAppliedReadback() } }
                        .disabled(coordinator.busy || readback.state == .reading)
                }.accessibilityIdentifier("ncm47.pin.receiptAndCurrentList")
            }
            NativeChannelMessageEditRecallRecoveryView(coordinator: coordinator)
            if coordinator.historyRefreshFailed {
                Button { Task { await coordinator.refreshHistory() } } label: { Text("history.retry", tableName: "NativeChannelMessage") }
            }
        }.padding(.horizontal, Theme.Space.pageX)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ncm47.recovery")
    }
}
