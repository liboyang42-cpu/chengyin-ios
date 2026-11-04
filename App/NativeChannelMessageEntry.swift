import SwiftUI

/// Wrap the EXISTING normal channel history/composer. It never creates a conversation,
/// send client, grant, URLSession or an independent message list.
@MainActor struct NativeChannelMessageEntry<Content: View>: View {
    @State var coordinator: NativeChannelMessageCoordinator
    @ViewBuilder let originalContent: () -> Content
    var locateOriginalMessage: ((NativeChannelMessageID) -> Void)?
    @State private var showingPins = false
    @State private var showingSearch = false
    @State private var pendingLocation:NativeChannelMessageID?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: Theme.Space.s2) {
            if coordinator.isCurrent && coordinator.client.allows(.mutations) {
                // ConversationHost filters payloads with canDisplay until the same-response
                // metadata is ready; keep the ORIGINAL failed-read recovery controls reachable.
                if !coordinator.historyReady { Text("source.required", tableName: "NativeChannelMessage").nativeChannelNotice(systemImage: "arrow.triangle.2.circlepath") }
                originalContent()
            }
            else { VStack(spacing: 12) { Image(systemName: "bubble.left"); Text("source.required", tableName: "NativeChannelMessage") }.padding() }
            NativeChannelMessageRecoveryView(coordinator: coordinator)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingPins = true } label: { Image(systemName: "pin") }
                    .accessibilityLabel(Text("pins.title", tableName: "NativeChannelMessage"))
                    .disabled(!coordinator.isCurrent || !coordinator.client.allows(.pins))
                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel(Text("search.title", tableName: "NativeChannelMessage"))
                    .disabled(!coordinator.isCurrent || !coordinator.client.allows(.search))
            }
        }
        .sheet(isPresented: $showingPins,onDismiss:finishLocation) { NavigationStack { NativeChannelMessagePinsView(coordinator: coordinator, locateOriginal: {pendingLocation=$0;showingPins=false}) } }
        .sheet(isPresented: $showingSearch,onDismiss:finishLocation) { NavigationStack { NativeChannelMessageSearchView(model: coordinator.search, locateOriginal: {pendingLocation=$0;showingSearch=false}) } }
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
                if let message = coordinator.lastFailure?.message, !message.isEmpty { Text(verbatim: message).font(.caption) }
                if code == "MESSAGE_VERSION_CONFLICT" { Text("message.changed", tableName: "NativeChannelMessage").font(.caption) }
                Button { coordinator.acknowledgeRejected() } label: { Text("request.keepDraft", tableName: "NativeChannelMessage") }
            case .persistenceFailed: Text("request.storage", tableName: "NativeChannelMessage")
            case .applied(let redacted): Text(redacted ? "request.redacted" : "request.applied", tableName: "NativeChannelMessage")
            case .accessClosed: Text("access.closed", tableName: "NativeChannelMessage")
            case .idle: EmptyView()
            }
            if coordinator.isCurrent, let pending = coordinator.original,
               pending.operation == .pin || pending.operation == .unpin {
                Text(verbatim: copy.format("p23.pending", pending.requestID, copy.operation(pending.operation), pending.messageID?.rawValue ?? "")).font(Theme.Font.label).monospaced().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(copy.text("p23.pending.explanation"))
            }
            if coordinator.isCurrent, coordinator.original == nil, let readback = coordinator.pins.appliedReadback {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: copy.format("p23.applied", copy.operation(readback.operation), readback.messageID.rawValue))
                    Text(verbatim: copy.format("p23.receipt", readback.requestID)).font(Theme.Font.label).monospaced().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    switch readback.state {
                    case .reading: Text(copy.text("p23.current.reading"))
                    case .matches: Text(copy.text("p23.current.matches"))
                    case .differs: Text(copy.text("p23.current.differs"))
                    case .failed: Text(copy.text("p23.current.failed"))
                    }
                    Button(copy.text("p23.current.refresh")) { Task { await coordinator.pins.refreshAppliedReadback() } }
                        .disabled(coordinator.busy || readback.state == .reading)
                }.accessibilityIdentifier("ncm47.pin.receiptAndCurrentList")
            }
            NativeChannelMessageEditRecallRecoveryView(coordinator: coordinator)
            if coordinator.historyRefreshFailed {
                Button { Task { await coordinator.refreshHistory() } } label: { Text("history.retry", tableName: "NativeChannelMessage") }
            }
        }.padding(Theme.Space.s3)
            .font(Theme.Font.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.bgPage(in: domain))
            .accessibilityIdentifier("ncm47.recovery")
    }
}
