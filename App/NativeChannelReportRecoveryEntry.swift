import SwiftUI

/// Normal 我的 → 消息 destination, outside every channel host/history gate.
@MainActor struct NativeChannelReportRecoveryEntry: View {
    @ObservedObject var session: AppSession
    @Environment(\.themeDomain) private var domain
    @Environment(\.scenePhase) private var scenePhase
    @State private var directory: NativeChannelReportRecoveryDirectory?
    @State private var visible = false
    var body: some View {
        Group {
            if scenePhase == .active, let directory, directory.isCurrent {
                NativeChannelReportRecoveryView(directory: directory)
            } else {
                ContentUnavailableView {
                    Label { Text("directory.unavailable", tableName: "NativeChannelReport") } icon: { Image(systemName: "lock.shield") }
                } actions: {
                    Button { reopen() } label: { Text("messaging.retry") }
                        .buttonStyle(.bordered)
                        .disabled(scenePhase != .active)
                        .accessibilityIdentifier("channel.reportRecovery.reopen")
                }
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .nativeChannelFlowPage()
        .navigationTitle(Text("d7.channelReport.statusTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = true; reopen() }
        .onDisappear { visible = false; suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reopen() } else { suspend() }
        }
        .onChange(of: session.messagingViewIdentity) { _, _ in reopen() }
        .privacySensitive()
        .tint(Theme.Color.accent(in: domain))
    }
    private func suspend() { directory?.retire(); directory = nil }
    private func reopen() {
        suspend()
        guard visible, scenePhase == .active else { return }
        directory = session.makeNativeChannelReportRecoveryDirectory()
        directory?.reload()
    }
}

/// Presentation identity is separate from the durable request UUID. A delayed
/// dismissal from one sheet cannot replace/close a newer original-request sheet.
@MainActor struct NativeChannelReportRecoveryNavigation {
    struct Route: Identifiable {
        let id = UUID()
        let entry: NativeChannelReportRecoveryDirectory.Entry
    }
    private(set) var selection: Route?
    mutating func open(_ entry: NativeChannelReportRecoveryDirectory.Entry,
                       directory: NativeChannelReportRecoveryDirectory) {
        guard selection == nil, directory.isCurrent, entry.owner.isCurrent, entry.owner.hasPending,
              directory.visibleEntries.contains(where: { $0.id == entry.id && $0.owner === entry.owner }) else { return }
        selection = Route(entry: entry)
    }
    mutating func close(_ id: UUID?) {
        guard selection?.id == id else { return }
        selection = nil
    }
}

@MainActor struct NativeChannelReportRecoveryView: View {
    @Bindable var directory: NativeChannelReportRecoveryDirectory
    @State private var navigation = NativeChannelReportRecoveryNavigation()
    var body: some View {
        Form {
            if directory.isCurrent {
                if directory.state == .unavailable || directory.hasUnreadableRecords {
                    Section {
                        Label { Text("directory.readFailed", tableName: "NativeChannelReport") } icon: { Image(systemName: "exclamationmark.triangle") }
                    }.accessibilityIdentifier("channel.reportRecovery.readFailed")
                }
                if directory.state == .ready {
                    if directory.visibleEntries.isEmpty && !directory.hasUnreadableRecords {
                        ContentUnavailableView { Label { Text("directory.empty", tableName: "NativeChannelReport") } icon: { Image(systemName: "flag") } }
                            .accessibilityIdentifier("channel.reportRecovery.empty")
                    }
                    if !directory.visibleEntries.isEmpty {
                        Section {
                            ForEach(Array(directory.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    navigation.open(entry, directory: directory)
                                } label: {
                                    LabeledContent { Text("d7.channelReport.waiting") } label: { Text("d7.channelReport.item \(index + 1)") }
                                        .frame(minHeight: 44)
                                }
                                .accessibilityIdentifier("channel.reportRecovery.request.\(entry.requestID)")
                            }
                        }
                    }
                }
            } else {
                Section { Text("directory.unavailable", tableName: "NativeChannelReport") }
            }
        }
        .formStyle(.grouped)
        .refreshable { if directory.isCurrent { directory.reload() } }
        .sheet(item: selectionBinding, onDismiss: {
            // An older dismissal must not invalidate a newer sheet's owner.
            if navigation.selection == nil, directory.isCurrent { directory.reload() }
        }) { route in
            NavigationStack { NativeChannelReportRecoveryDetail(owner: route.entry.owner) }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .privacySensitive()
    }
    private var selectionBinding: Binding<NativeChannelReportRecoveryNavigation.Route?> {
        let captured = navigation.selection?.id
        return Binding(get: { navigation.selection }, set: { value in
            if value == nil { navigation.close(captured) }
        })
    }
}

/// Does not render the journal's reason, note, message ID, or retired channel content.
/// Even NOT_FOUND + retry permission remains read-only in this membership-free host.
@MainActor struct NativeChannelReportRecoveryDetail: View {
    @Bindable var owner: NativeChannelReportFlow
    @Environment(\.themeDomain) private var domain
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var readTask: Task<Void, Never>?
    var body: some View {
        Form {
            if scenePhase == .active && owner.isCurrent {
                Section {
                    switch owner.state {
                    case .reading:
                        ProgressView { Text("recovery.reading", tableName: "NativeChannelReport") }
                    case .acknowledged(_, let status):
                        Label { Text("recovery.confirmed", tableName: "NativeChannelReport") } icon: { Image(systemName: "checkmark.circle") }
                        LabeledContent {
                            NativeChannelReportPresentation.status(status)
                                .accessibilityIdentifier("channel.reportRecovery.status")
                        } label: { Text("d7.channelReport.status") }
                    case .unknown:
                        NativeChannelFlowNotice(title:Text("recovery.unknown", tableName: "NativeChannelReport"),symbol:"clock.arrow.circlepath")
                    case .idle, .reviewing, .submitting, .unavailable:
                        Text("directory.readFailed", tableName: "NativeChannelReport")
                    }
                    if owner.hasPending {
                        if owner.canRecover || readTask != nil {
                            Button {
                                guard readTask == nil, owner.canRecover else { return }
                                readTask = Task { @MainActor in await owner.recover(); readTask = nil }
                            } label: { Text("recovery.read", tableName: "NativeChannelReport") }
                                .disabled(!owner.canRecover || readTask != nil)
                                .accessibilityIdentifier("channel.reportRecovery.read")
                        } else if owner.state != .reading {
                            Text("recovery.noGrant", tableName: "NativeChannelReport")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                ContentUnavailableView { Label { Text("directory.unavailable", tableName: "NativeChannelReport") } icon: { Image(systemName: "lock.shield") } }
            }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .nativeChannelFlowPage()
        .navigationTitle(Text("d7.channelReport.statusTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Text("recovery.close", tableName: "NativeChannelReport") }
                .accessibilityIdentifier("channel.reportRecovery.close")
        } }
        .onDisappear { readTask?.cancel(); readTask = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { readTask?.cancel(); readTask = nil }
        }
        .privacySensitive()
        .tint(Theme.Color.accent(in: domain))
    }
}
