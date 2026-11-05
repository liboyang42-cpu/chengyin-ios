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
                Form {
                    Section {
                        Label { Text("directory.unavailable", tableName: "NativeChannelReport") } icon: { Image(systemName: "lock.shield") }
                        Text("directory.preserved", tableName: "NativeChannelReport")
                            .fixedSize(horizontal: false, vertical: true)
                        Button { reopen() } label: { Text("directory.reload", tableName: "NativeChannelReport") }
                            .disabled(scenePhase != .active)
                            .accessibilityIdentifier("channel.reportRecovery.reopen")
                    }
                }.formStyle(.grouped)
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .nativeChannelFlowPage()
        .navigationTitle(Text("recovery.title", tableName: "NativeChannelReport"))
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
                Section {
                    Text("directory.scope", tableName: "NativeChannelReport")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("directory.readOnly", tableName: "NativeChannelReport")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if directory.state == .unavailable || directory.hasUnreadableRecords {
                    Section {
                        Label { Text("directory.readFailed", tableName: "NativeChannelReport") } icon: { Image(systemName: "exclamationmark.triangle") }
                        Text("directory.preserved", tableName: "NativeChannelReport")
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("channel.reportRecovery.readFailed")
                }
                if directory.state == .ready {
                    if directory.visibleEntries.isEmpty && !directory.hasUnreadableRecords {
                        Section { Text("directory.empty", tableName: "NativeChannelReport") }
                            .accessibilityIdentifier("channel.reportRecovery.empty")
                    }
                    ForEach(directory.visibleEntries) { entry in
                        Section {
                            Button {
                                navigation.open(entry, directory: directory)
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                                    Label { Text("recovery.pending", tableName: "NativeChannelReport") } icon: { Image(systemName: "clock.arrow.circlepath") }
                                    Text(verbatim: entry.requestID).font(.callout.monospaced())
                                        .fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("channel.reportRecovery.request.\(entry.requestID)")
                            if !entry.owner.canRecover && entry.owner.state != .reading {
                                Text("recovery.noGrant", tableName: "NativeChannelReport")
                                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Section {
                    Button { directory.reload() } label: { Text("directory.reload", tableName: "NativeChannelReport") }
                        .accessibilityIdentifier("channel.reportRecovery.reload")
                }
            } else {
                Section { Text("directory.unavailable", tableName: "NativeChannelReport") }
            }
        }
        .formStyle(.grouped)
        .sheet(item: selectionBinding, onDismiss: {
            // An older dismissal must not invalidate a newer sheet's owner.
            if navigation.selection == nil, directory.isCurrent { directory.reload() }
        }) { route in
            NavigationStack { NativeChannelReportRecoveryDetail(owner: route.entry.owner) }
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
                if let request = owner.requestID {
                    Section {
                        Text("recovery.requestID", tableName: "NativeChannelReport").font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: request).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Text("recovery.requestID", tableName: "NativeChannelReport"))
                            .accessibilityValue(request)
                            .accessibilityIdentifier("channel.reportRecovery.requestID")
                    }
                }
                Section {
                    switch owner.state {
                    case .reading:
                        ProgressView { Text("recovery.reading", tableName: "NativeChannelReport") }
                    case .acknowledged(let reportID, let status):
                        Label { Text("recovery.confirmed", tableName: "NativeChannelReport") } icon: { Image(systemName: "checkmark.circle") }
                        LabeledContent { Text(verbatim: reportID).textSelection(.enabled) } label: {
                            Text("recovery.reportID", tableName: "NativeChannelReport")
                        }
                        Text("recovery.statusAtRead", tableName: "NativeChannelReport").font(.headline)
                        Text(LocalizedStringKey("status." + status), tableName: "NativeChannelReport")
                            .accessibilityIdentifier("channel.reportRecovery.status")
                        Text(verbatim: status).font(.caption)
                        Text("recovery.statusBoundary", tableName: "NativeChannelReport")
                            .fixedSize(horizontal: false, vertical: true)
                    case .unknown:
                        NativeChannelFlowNotice(title:Text("recovery.unknown", tableName: "NativeChannelReport"),symbol:"clock.arrow.circlepath")
                    case .idle, .reviewing, .submitting, .unavailable:
                        Text("directory.readFailed", tableName: "NativeChannelReport")
                    }
                    if owner.hasPending {
                        Button {
                            guard readTask == nil, owner.canRecover else { return }
                            readTask = Task { @MainActor in await owner.recover(); readTask = nil }
                        } label: { Text("recovery.read", tableName: "NativeChannelReport") }
                            .disabled(!owner.canRecover || readTask != nil)
                            .accessibilityIdentifier("channel.reportRecovery.read")
                        if !owner.canRecover && owner.state != .reading {
                            Text("recovery.noGrant", tableName: "NativeChannelReport")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section {
                    Text("directory.readOnly", tableName: "NativeChannelReport")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section { Text("directory.unavailable", tableName: "NativeChannelReport") }
            }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .nativeChannelFlowPage()
        .navigationTitle(Text("recovery.title", tableName: "NativeChannelReport"))
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
