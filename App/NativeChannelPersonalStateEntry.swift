import SwiftUI

@MainActor struct NativeChannelPersonalStateEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelPersonalStateFlow?
    @State private var flow: NativeChannelPersonalStateFlow?
    @State private var generation = 0
    @State private var retryConfirmation = false
    @State private var attempted = false
    /// Presentation copy for the change under review; Core keeps the real request.
    @State private var reviewing: Review?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private struct Review: Equatable { let field: NativeChannelPersonalStateFlow.Field; let value: Bool }
    var body: some View {
        Group {
            if let flow,flow.isCurrent {
                Form {
                    if showsStatus(flow) {
                        Section {
                            if flow.state == .loading || flow.state == .submitting || flow.readingCurrent { ProgressView() }
                            if flow.state == .unknown { NativeChannelFlowNotice(title:Text("d7.channelPersonal.unknown"),symbol:"clock.arrow.circlepath") }
                            if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("d7.channelPersonal.unavailable"),symbol:"lock") }
                            if flow.currentReadFailed { Text("d7.channelPersonal.readFailed") }
                            if flow.state == .appliedHidden { Text("d7.channelPersonal.appliedHidden") }
                            if flow.hasPending {
                                Button("d7.channelPersonal.check") { Task { await flow.refresh() } }.disabled(!flow.canRecover)
                                Button("d7.channelPersonal.retry") { retryConfirmation=true }.disabled(!flow.canRetry)
                            }
                        }
                    }
                    if let value=flow.currentState {
                        Section {
                            Button(LocalizedStringKey(value.pinned ? "d7.channelPersonal.unpin" : "d7.channelPersonal.pin")) { prepare(flow,.pinned,!value.pinned) }
                            Button(LocalizedStringKey(value.hidden ? "d7.channelPersonal.show" : "d7.channelPersonal.hide")) { prepare(flow,.hidden,!value.hidden) }
                        } header: { Text("d7.channelPersonal.list") }
                        .disabled(!flow.canPrepare)
                        Section {
                            LabeledContent { Text(muteStatus(value)) } label: { Text("d7.channelPersonal.mute") }
                            if !value.permanentMuted {
                                Button("d7.channelPersonal.muteOn") { prepare(flow,.muted,true) }.disabled(!flow.canPrepare)
                            }
                            if value.muted || value.permanentMuted || value.mutedUntil != nil {
                                Button("d7.channelPersonal.muteOff") { prepare(flow,.muted,false) }.disabled(!flow.canPrepare)
                            }
                        } header: { Text("d7.channelPersonal.notifications") }
                    }
                    if flow.state == .reviewing {
                        Section {
                            if let reviewing { Text(LocalizedStringKey(reviewKey(reviewing))).fixedSize(horizontal:false,vertical:true) }
                            Button("d7.channelPersonal.confirm") { Task { await flow.confirm() } }.nativeChannelFlowAction()
                            Button("d7.channelPersonal.cancel") { flow.cancelReview() }
                        }
                    }
                }
                .refreshable { await flow.refresh() }
                .confirmationDialog("d7.channelPersonal.retryConfirm",isPresented:$retryConfirmation,titleVisibility:.visible) {
                    Button("d7.channelPersonal.retry") { Task { await flow.retryOriginal() } }
                    Button("d7.channelPersonal.cancel",role:.cancel) {}
                }
            } else if attempted {
                ContentUnavailableView {
                    Label("d7.channelPersonal.unavailableTitle", systemImage: "pin.slash")
                } actions: {
                    Button("d7.channelPersonal.reload") { Task { await open() } }
                }
            } else { ProgressView() }
        }
        .nativeChannelFlowPage()
        .navigationTitle(Text("d7.channelPersonal.title"))
        .task { await open() }
        .task { while !Task.isCancelled { if let flow,!flow.isCurrent { close() };do { try await Task.sleep(nanoseconds:500_000_000) } catch { return } } }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }.privacySensitive()
    }
    private func showsStatus(_ flow: NativeChannelPersonalStateFlow) -> Bool {
        if flow.readingCurrent || flow.currentReadFailed || flow.hasPending { return true }
        switch flow.state {
        case .loading, .submitting, .unknown, .unavailable, .appliedHidden: return true
        default: return false
        }
    }
    private func prepare(_ flow: NativeChannelPersonalStateFlow,_ field: NativeChannelPersonalStateFlow.Field,_ value: Bool) {
        reviewing = Review(field: field, value: value)
        flow.prepare(field,value:value)
    }
    private func reviewKey(_ review: Review) -> String {
        switch review.field {
        case .pinned: return review.value ? "d7.channelPersonal.review.pin" : "d7.channelPersonal.review.unpin"
        case .hidden: return review.value ? "d7.channelPersonal.review.hide" : "d7.channelPersonal.review.show"
        case .muted: return review.value ? "d7.channelPersonal.review.mute" : "d7.channelPersonal.review.unmute"
        }
    }
    private func muteStatus(_ value: NativeChannelPersonalStateFlow.Snapshot) -> String {
        if value.permanentMuted { return appLocalized("d7.channelPersonal.mutedOn", locale: locale) }
        if let until = value.mutedUntil {
            let shown = NativeChannelNotificationCommand.instant(until).map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)) } ?? until
            return String(format: appLocalized("d7.channelPersonal.mutedUntil", locale: locale), locale: locale, shown)
        }
        if value.muted { return appLocalized("d7.channelPersonal.mutedOn", locale: locale) }
        return appLocalized("d7.channelPersonal.mutedOff", locale: locale)
    }
    private func close() { generation += 1;flow?.deactivate();flow=nil;retryConfirmation=false }
    private func open() async {
        close();attempted=false;let run=generation
        defer { if run == generation { attempted=true } }
        do {
            let captured=try await channels.currentChannelContext(channelID:channelID)
            guard run == generation,scenePhase == .active,!Task.isCancelled,channels.contextIsCurrent(captured),let owner=makeFlow(captured) else { return }
            await owner.activate();guard run == generation,scenePhase == .active,!Task.isCancelled else { owner.deactivate();return };flow=owner
        } catch { }
    }
}
