import SwiftUI

@MainActor struct NativeChannelModerationEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelModerationFlow?
    @State private var flow: NativeChannelModerationFlow?
    @State private var generation = 0
    @State private var unavailable = false
    @State private var target = ""
    @State private var reason = ""
    @State private var reasonCode = "NOISE"
    @State private var seconds = "600"
    @State private var deleteMessageSeconds = "0"
    @State private var operation: NativeChannelModerationFlow.Operation = .timeout
    @State private var retryConfirmation = false
    @State private var invalidDraft = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let flow, flow.isCurrent {
                Form {
                    if flow.hasPending || flow.state == .unknown || flow.state == .unavailable || flow.state == .loading || flow.state == .submitting || flow.result != nil {
                        Section {
                            if flow.hasPending {
                                NativeChannelFlowNotice(title:Text("d7.channelModeration.pending"),symbol:"clock.arrow.circlepath")
                                Button("d7.channelModeration.checkStatus") { Task { await flow.refresh() } }.disabled(!flow.canRecover)
                                if flow.canRetry { Button("d7.channelModeration.retry") { retryConfirmation = true } }
                            } else if flow.state == .unknown {
                                NativeChannelFlowNotice(title:Text("d7.channelModeration.unknown"),symbol:"clock.arrow.circlepath")
                            }
                            if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("d7.channelModeration.unavailableState"),symbol:"lock.shield") }
                            if flow.state == .loading || flow.state == .submitting { ProgressView().frame(maxWidth:.infinity) }
                            if let result = flow.result {
                                NativeChannelFlowNotice(title:Text("d7.channelModeration.saved"),symbol:"checkmark.circle")
                                LabeledContent("d7.channelModeration.action") { typeText(result.type) }
                                LabeledContent("d7.channelModeration.status") { statusText(result.status) }
                            }
                        }
                    }
                    if !flow.hasPending {
                        Section("d7.channelModeration.newAction") {
                            Picker("d7.channelModeration.action",selection:$operation) {
                                Text("d7.channelModeration.op.timeout").tag(NativeChannelModerationFlow.Operation.timeout)
                                Text("d7.channelModeration.op.kick").tag(NativeChannelModerationFlow.Operation.kick)
                                Text("d7.channelModeration.op.ban").tag(NativeChannelModerationFlow.Operation.ban)
                            }
                            LabeledContent("d7.channelModeration.member") {
                                TextField(text:$target,prompt:Text(verbatim:"0")) { Text("d7.channelModeration.member") }
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            }
                            if operation != .kick {
                                LabeledContent("d7.channelModeration.duration") {
                                    TextField(text:$seconds,prompt:Text(verbatim:"600")) { Text("d7.channelModeration.duration") }
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                }
                            }
                            if operation == .ban {
                                LabeledContent("d7.channelModeration.deleteMessages") {
                                    TextField(text:$deleteMessageSeconds,prompt:Text(verbatim:"0")) { Text("d7.channelModeration.deleteMessages") }
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                }
                                Text("d7.channelModeration.deleteWarning").foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)
                            }
                            Picker("d7.channelModeration.reasonType",selection:$reasonCode) {
                                Text("d7.channelModeration.reason.NOISE").tag("NOISE")
                                ForEach(NativeChannelReportReason.allCases) { reason in
                                    Text(LocalizedStringKey("d7.channelModeration.reason." + reason.rawValue)).tag(reason.rawValue)
                                }
                            }
                            TextField("d7.channelModeration.details",text:$reason,axis:.vertical).lineLimit(3...7)
                            if invalidDraft { Text("d7.channelModeration.invalid").foregroundStyle(.red).fixedSize(horizontal:false,vertical:true) }
                        }
                        Section {
                            Button("d7.channelModeration.review") {
                                invalidDraft = !flow.prepare(operation,target:target,seconds:operation == .kick ? 0 : (Int(seconds) ?? -1),reasonCode:reasonCode,reason:reason,deleteMessageSeconds:operation == .ban ? (Int(deleteMessageSeconds) ?? -1) : 0)
                            }.nativeChannelFlowAction().disabled(!flow.canPrepare(operation))
                        }
                    }
                    if flow.state == .reviewing {
                        Section("d7.channelModeration.confirmTitle") {
                            Text(flow.reviewedSummary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                            Button("d7.channelModeration.confirm",role:.destructive) { Task { await flow.confirm() } }.nativeChannelFlowAction()
                        }
                        Section { Button("d7.channelModeration.cancel") { flow.cancelReview() } }
                    }
                    Section("d7.channelModeration.history") {
                        if flow.readingCurrent { ProgressView().frame(maxWidth:.infinity) }
                        if flow.currentReadFailed { Text("d7.channelModeration.historyFailed").foregroundStyle(.secondary) }
                        ForEach(flow.actions) { action in
                            VStack(alignment:.leading,spacing:Theme.Space.s1) {
                                HStack(alignment:.firstTextBaseline) {
                                    typeText(action.type).font(Theme.Font.sectionTitle)
                                    Spacer(minLength:Theme.Space.s2)
                                    statusText(action.status).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text("d7.channelModeration.memberValue \(action.target)").font(.subheadline).foregroundStyle(.secondary)
                                if !action.reason.isEmpty { Text(action.reason).fixedSize(horizontal:false,vertical:true) }
                                if !action.expiresAt.isEmpty { Text("d7.channelModeration.expires \(action.expiresAt)").font(.footnote).foregroundStyle(.secondary) }
                            }
                            .padding(.vertical,Theme.Space.s1)
                            .swipeActions(edge:.trailing) {
                                if flow.canRevoke(action) {
                                    Button("d7.channelModeration.revoke",role:.destructive) { invalidDraft = !flow.prepareRevoke(action,reason:reason) }
                                }
                            }
                        }
                        if flow.state == .ready && flow.actions.isEmpty && !flow.readingCurrent && !flow.currentReadFailed {
                            Text("d7.channelModeration.historyEmpty").foregroundStyle(.secondary)
                        }
                        if flow.canReadMore { Button("d7.channelModeration.loadMore") { Task { await flow.loadMore() } } }
                    }
                }
                .refreshable { await flow.refresh() }
                .confirmationDialog("d7.channelModeration.retryTitle",isPresented:$retryConfirmation,titleVisibility:.visible) {
                    Button("d7.channelModeration.retry",role:.destructive) { Task { await flow.retryOriginal() } }
                    Button("d7.channelModeration.cancel",role:.cancel) { }
                }
            } else if unavailable {
                ContentUnavailableView {
                    Label("d7.channelModeration.unavailable",systemImage:"lock.shield")
                } actions: {
                    Button("d7.channelModeration.tryAgain") { Task { await open() } }
                }
            } else {
                ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle("d7.channelModeration.title")
        .task { await open() }
        .task {
            while !Task.isCancelled {
                if let flow, !flow.isCurrent { close(); unavailable = true }
                do { try await Task.sleep(nanoseconds:500_000_000) } catch { return }
            }
        }
        .onDisappear { close() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await open() } } else { close() } }
        .privacySensitive()
    }
    /// Server action types are compared verbatim; unknown values pass through as sent.
    @ViewBuilder private func typeText(_ type: String) -> some View {
        switch type {
        case "TIMEOUT": Text("d7.channelModeration.op.timeout")
        case "KICK": Text("d7.channelModeration.op.kick")
        case "BAN": Text("d7.channelModeration.op.ban")
        default: Text(verbatim: type)
        }
    }
    @ViewBuilder private func statusText(_ status: String) -> some View {
        switch status {
        case "ACTIVE": Text("d7.channelModeration.status.active")
        case "REVOKED": Text("d7.channelModeration.status.revoked")
        case "EXPIRED": Text("d7.channelModeration.status.expired")
        default: Text(verbatim: status)
        }
    }
    private func close() { generation += 1; flow?.deactivate();flow = nil;target = "";reason = "";deleteMessageSeconds = "0";retryConfirmation = false;invalidDraft = false }
    private func open() async {
        close();unavailable = false;let run = generation
        do {
            let captured = try await channels.currentChannelContext(channelID:channelID)
            guard run == generation,scenePhase == .active,!Task.isCancelled,channels.contextIsCurrent(captured),
                  let owner = makeFlow(captured) else { if run == generation { unavailable = true };return }
            await owner.activate()
            guard run == generation,scenePhase == .active,!Task.isCancelled else { owner.deactivate();return }
            flow = owner;unavailable = !owner.isCurrent
        } catch { if run == generation { unavailable = true } }
    }
}
