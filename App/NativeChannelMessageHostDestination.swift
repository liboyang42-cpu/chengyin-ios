import SwiftUI

/// Normal entry uses a freshly read real channel and the original IM conversation row.
/// It does not infer an action grant from either source or silently downgrade references.
@MainActor struct NativeChannelMessageHostDestination: View {
    @ObservedObject var session: AppSession
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    // Actual parent NavigationLink/path membership; true while a child is pushed.
    let routeIsPresented: Binding<Bool>
    @Environment(\.scenePhase) private var scenePhase
    @State private var flow: NativeChannelMessageHostFlow?
    @State private var notificationFlow: NativeChannelNotificationCoordinator?
    @State private var mentionsPresented = false
    @State private var loading = false
    @State private var unavailable = false
    @State private var generation: UInt64 = 0
    @State private var openingTask: Task<Void, Never>?
    @State private var monitorTask: Task<Void, Never>?
    @State private var contextSelection: NativeChannelContextSelection?
    @State private var selected: MessagingMessage?
    var body: some View {
        Group {
            if let flow, flow.isCurrent {
                NativeChannelMessageConversationHost(history: flow.history, coordinator: flow.coordinator, wire: flow.wire,
                    makeTextCoordinator: { flow.makeTextCoordinator(history: $0) },
                    makePageActions: { flow.pageActions(history: $0, textCoordinator: $1) },
                    mediaReader: session.socialMessageMediaReader,
                    expanded: session.nativeChannelMessageExpandedNavigation(for: flow),
                    locateOriginal: { id in
                        guard flow.isCurrent,flow.coordinator.client.allows(.context) else {unavailable=true;return}
                        contextSelection = .init(id:id)
                    }, quoteUsingOriginalJournal: { id in
                        if !flow.prepareOriginalQuote(id) { unavailable = true }
                    }, reportUsingExistingOwner: nil,
                    reportFlow: session.nativeChannelReportFlow(for: flow), notificationFlow: notificationFlow,
                    historyRouteIsActive: { routeIsPresented.wrappedValue && scenePhase == .active && flow.isCurrent })
            } else {
                VStack(spacing: Theme.Space.s3) {
                    Text("source.required", tableName: "NativeChannelMessage").nativeChannelNotice(systemImage: "bubble.left")
                    if loading { ProgressView() }
                    else { Button("Retry") { resume() }.buttonStyle(.bordered).frame(minHeight: 44) }
                }.padding()
            }
        }
        .nativeChannelScreen()
        .toolbar {
            if let flow,flow.canOpenMentionTargets { Button("提及目标与恢复",systemImage:"at") { mentionsPresented=true } }
        }
        .sheet(isPresented:$mentionsPresented) {
            if let flow,flow.canOpenMentionTargets,let targets=flow.mentionTargets {
                NavigationStack { NativeChannelMentionEntry(source:targets,original:flow.originalDraftReference,canApply:{ flow.canPrepareMentions },apply:flow.prepareOriginalMentions) }
            } else { Text("原提及来源或发送授权不可用") }
        }
        .onAppear { resume() }
        .onChange(of: session.contentDetailRevision) { _, _ in close(); resume() }
        .onChange(of: routeIsPresented.wrappedValue) { _, presented in
            if presented { resume() } else { close() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resume() } else { close() }
        }
        .onDisappear {
            if !routeIsPresented.wrappedValue || scenePhase != .active || flow?.isCurrent == false { close() }
        }
        .sheet(item:$contextSelection) { target in
            if let flow,flow.isCurrent {
                NativeChannelMessageContextEntry(model:.init(client:flow.coordinator.client,selected:target.id),expanded:{ model in
                    session.nativeChannelMessageExpandedNavigation(for:flow,contextMessageIsCurrent:{ [weak model] message in
                        model?.currentMessage(id:message.id)==message
                    })
                })
            }
        }
        .sheet(item: $selected) { message in
            if let flow, flow.isCurrent {
                NavigationStack {
                    MessagingMessageDetailView(message: message, conversation: flow.history.conversation,
                        reader: flow.reader, identity: flow.reader.identity,
                        mediaReader: session.socialMessageMediaReader,
                        expanded: session.nativeChannelMessageExpandedNavigation(for: flow), currentMessage: {
                            guard flow.isCurrent, let row = flow.history.detailMessage(message.id),
                                  let snapshot = flow.wire.snapshot(for: row), flow.coordinator.canDisplay(snapshot) else { return nil }
                            return row
                        })
                }
            }
        }
        .alert(Text("message.unavailable", tableName: "NativeChannelMessage"), isPresented: $unavailable) { Button("OK", role: .cancel) {} }
        .privacySensitive()
    }
    private func close() {
        generation &+= 1
        openingTask?.cancel(); openingTask = nil
        monitorTask?.cancel(); monitorTask = nil
        contextSelection = nil; mentionsPresented = false
        notificationFlow?.deactivate(); notificationFlow = nil
        flow?.retire(); flow = nil; selected = nil; loading = false
    }
    private func resume() {
        guard routeIsPresented.wrappedValue, scenePhase == .active else { close(); return }
        if let flow, flow.isCurrent { monitor(); return }
        guard openingTask == nil else { return }
        close(); loading = true
        let run = generation
        openingTask = Task { await open(run: run) }
        monitor()
    }
    private func monitor() {
        guard monitorTask == nil else { return }
        // Unlike a view .task, this route-owned monitor survives covering child pushes.
        monitorTask = Task { @MainActor in
            while !Task.isCancelled {
                guard routeIsPresented.wrappedValue, scenePhase == .active else { close(); return }
                if let current = flow, !current.isCurrent { close(); return }
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            }
        }
    }
    private func open(run: UInt64) async {
        defer { if run == generation { loading = false; openingTask = nil } }
        guard run == generation, !Task.isCancelled, routeIsPresented.wrappedValue,
              scenePhase == .active else { return }
        let route = routeIsPresented // Capture the weak per-visit binding, not this state-owning View.
        let candidate = await session.makeNativeChannelMessageFlow(channels: channels, channelID: channelID,
            sourceCurrent: { route.wrappedValue })
        guard run == generation, !Task.isCancelled, routeIsPresented.wrappedValue,
              scenePhase == .active else { candidate?.retire(); return }
        loading = false; flow = candidate
        if let candidate, candidate.isCurrent,
           let scope = try? NativeChannelNotificationScope(type: 1, value: String(candidate.history.conversation.id)) {
            let notification = session.makeNativeChannelNotificationFlow(scope: scope,
                sourceCurrent: { [weak candidate] in candidate?.isCurrent == true && route.wrappedValue })
            notificationFlow = notification
            await notification?.activate() // original receipt/read recovery only; never automatically sends ACK
            guard run == generation, !Task.isCancelled, routeIsPresented.wrappedValue,
                  candidate.isCurrent, scenePhase == .active else {
                notification?.deactivate(); return
            }
        }
    }
}
