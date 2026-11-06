import SwiftUI

@MainActor private final class NativeFriendMetadataViewModel: ObservableObject {
    let flow: NativeFriendMetadataFlow
    init(_ flow: NativeFriendMetadataFlow, onApplied: @escaping () -> Void) {
        self.flow = flow; flow.onChange = { [weak self] in self?.objectWillChange.send() }; flow.onApplied = onApplied
    }
}

/// Opened only from a real row in the normal friends list. No numeric peer entry or parallel relationship store.
@MainActor struct NativeFriendMetadataView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: NativeFriendMetadataViewModel
    let nickname: String
    @State private var confirmingSettlement = false
    @State private var visit: UUID?
    @State private var visible = false
    @State private var settlementIdentity: NativeFriendMetadataFlow.PendingIdentity?
    @State private var remark = ""
    @State private var groupID: Int64?
    @State private var starred = false
    @State private var sharesProgress = false
    @State private var editingGroupID: Int64?
    @State private var groupName = ""
    @State private var position = 1
    @State private var deletingGroupID: Int64?
    @State private var destinationID: Int64?
    init(flow: NativeFriendMetadataFlow, nickname: String, onApplied: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: NativeFriendMetadataViewModel(flow, onApplied: onApplied)); self.nickname = nickname
    }
    private var flow: NativeFriendMetadataFlow { model.flow }
    var body: some View {
        Form {
            if flow.canPresentPeer { Section {
                HStack(spacing: Theme.Space.s3) {
                    Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(verbatim: nickname.isEmpty ? "—" : nickname).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                }
            } }
            if flow.busy { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("friendMeta.loading") }
            if !flow.isCurrent { text("friendMeta.closed") }
            if let issue = flow.issue {
                Label { text(issue) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("friendMeta.issue")
            }
            if flow.isCurrent, let recoveryIssue = flow.recoveryIssue {
                text(recoveryIssue).foregroundStyle(.secondary).accessibilityIdentifier("friendMeta.recoveryIssue")
            }
            if flow.pending != nil {
                Section {
                    if !flow.hasResolvedPending { text("friendMeta.unknown") }
                    Button { performPresented { await flow.recover() } } label: { text(flow.hasResolvedPending ? "friendMeta.retryCleanup" : "friendMeta.recover") }.disabled(!flow.canRecover)
                        .accessibilityIdentifier("friendMeta.recover")
                }
            }
            if flow.isCurrent, flow.resolvedIdentity != nil {
                if flow.didApply { text("friendMeta.saved").accessibilityIdentifier("friendMeta.saved") }
                else { text("friendMeta.notApplied").accessibilityIdentifier("friendMeta.notApplied") }
            }
            if let command = flow.review {
                Section {
                    reviewDetails(command)
                    Button { performPresented { await flow.confirm(expected: command) } } label: { text("friendMeta.confirm") }.disabled(!flow.canConfirm)
                        .accessibilityIdentifier("friendMeta.confirm")
                    Button { flow.cancelReview() } label: { text("friendMeta.cancel") }.disabled(flow.busy)
                } header: { text("friendMeta.reviewTitle") }
            }
            if flow.canPresentPeer && flow.metadata != nil {
                Section {
                    TextField(localized("d7.friendMeta.remarkPrompt"), text: $remark).accessibilityIdentifier("friendMeta.remark")
                    Button { flow.reviewMetadata(remark: remark, groupID: nil, starred: false) } label: { text("friendMeta.review") }
                        .accessibilityIdentifier("friendMeta.review")
                } header: { text("friendMeta.preferences") }.disabled(!flow.canEdit)
                if !flow.groups.isEmpty {
                    Section {
                        Picker(localized("friendMeta.group"), selection: $groupID) {
                            text("friendMeta.defaultGroup").tag(Int64?.none)
                            ForEach(flow.groups.filter { $0.isDefault == 0 }) { group in groupLabel(group).tag(group.id) }
                        }
                        Button { flow.reviewAssignment(groupID) } label: { text("friendMeta.review") }
                    } header: { text("friendMeta.group") }.disabled(!flow.canAssignGroup)
                }
                Section {
                    Toggle(isOn: $starred) { text("friendMeta.starred") }.accessibilityIdentifier("friendMeta.starred")
                    Button { flow.reviewStar(starred) } label: { text("friendMeta.review") }
                        .accessibilityIdentifier("friendMeta.reviewStar")
                }.disabled(!flow.canEditStar)
                Section {
                    Toggle(isOn: $sharesProgress) { text("d7.friendMeta.shareProgress") }
                    Button { flow.reviewProgress(sharesProgress) } label: { text("friendMeta.review") }
                }.disabled(!flow.canEditProgress)
            }
            if flow.isCurrent && !flow.groups.isEmpty {
                Section {
                    ForEach(flow.groups) { group in
                        HStack(spacing: Theme.Space.s2) {
                            groupLabel(group)
                            Spacer()
                            if let count = group.friendCount { Text("d7.friendMeta.friendCount \(count)", tableName: "NativeFriendMetadata").foregroundStyle(.secondary) }
                            if group.isDefault == 0 {
                                Menu {
                                    Button { editingGroupID=group.id;groupName=group.name;position=group.position } label: {
                                        Label { text("friendMeta.rename") } icon: { Image(systemName: "pencil") }
                                    }
                                    Button(role: .destructive) { deletingGroupID=group.id;destinationID=nil } label: {
                                        Label { text("friendMeta.delete") } icon: { Image(systemName: "trash") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").accessibilityLabel(Text("friendMeta.rename", tableName: "NativeFriendMetadata"))
                                }
                                .buttonStyle(.borderless)
                                .disabled(!flow.canManageGroups)
                            }
                        }
                    }
                } header: { text("d7.friendMeta.myGroups") }
                Section {
                    TextField(localized("friendMeta.groupName"),text:$groupName)
                    Stepper(value:$position,in:0...Int(Int32.max)) { Text("d7.friendMeta.order \(position)", tableName: "NativeFriendMetadata") }
                    Button { flow.reviewGroup(id:editingGroupID,name:groupName,position:position) } label: { text(editingGroupID == nil ? "friendMeta.createGroup" : "friendMeta.saveGroup") }
                    if editingGroupID != nil { Button { editingGroupID=nil;groupName="";position=1 } label: { text("friendMeta.newGroup") } }
                } header: { text(editingGroupID == nil ? "friendMeta.pendingGroupCreate" : "friendMeta.pendingGroupEdit") }
                    .disabled(!flow.canManageGroups)
                if let source=deletingGroupID {
                    Section {
                        groupNameLabel(source)
                        Picker(localized("friendMeta.moveTo"),selection:$destinationID) {
                            text("friendMeta.defaultGroup").tag(Int64?.none)
                            ForEach(flow.groups.filter { $0.isDefault == 0 && $0.id != source }) { group in groupLabel(group).tag(group.id) }
                        }
                        Button(role:.destructive) { flow.reviewDeleteGroup(id:source,moveTo:destinationID) } label: { text("friendMeta.reviewDelete") }
                        Button { deletingGroupID=nil;destinationID=nil } label: { text("friendMeta.cancel") }
                    } header: { text("friendMeta.delete") }.disabled(!flow.canManageGroups)
                }
            }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .navigationTitle(localized(flow.peerID == 0 ? "friendMeta.recoveryEntry" : "friendMeta.title"))
        .accessibilityIdentifier("friendMeta.editor").privacySensitive()
        .onAppear { visible = true; if scenePhase == .active { visit = UUID(); performPresented { await flow.load() } } }
        .onChange(of: flow.metadata) { _, _ in synchronize() }
        .onChange(of: flow.groups) { _, _ in
            if let id = editingGroupID, !flow.groups.contains(where: { $0.id == id }) { editingGroupID = nil; groupName = "" }
            deletingGroupID = nil; destinationID = nil
        }
        .refreshable { if !flow.busy { performPresented { await flow.load() } } }
        .onDisappear { visible = false; retirePresentation() }
        .onChange(of: flow.isCurrent) { _, current in if !current { retirePresentation() } }
        .onChange(of: scenePhase) { _, phase in
            retirePresentation()
            if phase == .active, visible { visit = UUID(); performPresented { await flow.load() } }
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private func performPresented(_ action: @escaping @MainActor () async -> Void) {
        guard visible, scenePhase == .active, let capturedVisit = visit else { return }
        let capturedFlow = flow
        Task { @MainActor in
            guard visible, scenePhase == .active, visit == capturedVisit, flow === capturedFlow else { return }
            await action()
            guard visible, scenePhase == .active, visit == capturedVisit, flow === capturedFlow else { return }
            synchronize()
        }
    }
    private func retirePresentation() { visit = nil; clearDraft(); flow.invalidate() }
    private func clearDraft() { remark = ""; groupID = nil; starred = false; sharesProgress = false; groupName = ""; editingGroupID = nil; deletingGroupID = nil; destinationID = nil; confirmingSettlement = false; settlementIdentity = nil }
    private func synchronize() { if flow.peerID == 0 { if !flow.isCurrent { clearDraft() };return };guard flow.canPresentPeer, let value = flow.metadata else { clearDraft(); return }; remark = value.remark ?? ""; starred = value.starred == 1; sharesProgress = value.progressScope == 1; groupID = value.groupID }
    @ViewBuilder private func reviewDetails(_ command: NativeFriendMetadataCommand) -> some View {
        switch command.action {
        case .remark:
            if command.updatesRemark {
                LabeledContent { Text(verbatim: command.remark ?? localized("friendMeta.nicknameFallback")) } label: { text("friendMeta.remark") }
            }
            if let scope = command.progressScope {
                LabeledContent { text(scope == 1 ? "friendMeta.starredOn" : "friendMeta.starredOff") } label: { text("d7.friendMeta.shareProgress") }
            }
            if command.updatesGroup { LabeledContent { groupNameLabel(command.groupID) } label: { text("friendMeta.group") } }
            if let starred = command.starred {
                LabeledContent { text(starred == 1 ? "friendMeta.starredOn" : "friendMeta.starredOff") } label: { text("friendMeta.starred") }
            }
        case .groupSave:
            LabeledContent { Text(verbatim: command.name ?? "—") } label: { text("friendMeta.groupName") }
            LabeledContent { Text(verbatim: "\(command.position ?? 0)") } label: { text("friendMeta.position") }
        case .groupDelete:
            LabeledContent { groupNameLabel(command.targetID) } label: { text("friendMeta.delete") }
            LabeledContent { groupNameLabel(command.groupID) } label: { text("friendMeta.moveTo") }
        }
    }
    @ViewBuilder private func groupNameLabel(_ id: Int64?) -> some View {
        if let group = flow.groups.first(where: { $0.id == id }) { groupLabel(group) } else { text("friendMeta.defaultGroup") }
    }
    @ViewBuilder private func groupLabel(_ group: NativeFriendMetadataGroup) -> some View {
        if group.isDefault == 1 { text("friendMeta.defaultGroup") } else { Text(verbatim: group.name) }
    }
    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeFriendMetadata", locale: locale))
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeFriendMetadata") }
}
