import SwiftUI

/// Attach to the original bubble. Missing source-owned actions are not forged here.
@MainActor struct NativeChannelMessageActionSheet: ViewModifier {
    @Bindable var coordinator: NativeChannelMessageCoordinator
    let snapshot: NativeChannelMessageSnapshot
    let currentSnapshot: () -> NativeChannelMessageSnapshot?
    var quoteUsingOriginalSend: ((NativeChannelMessageID) -> Void)?
    var reportUsingExistingOwner: ((NativeChannelMessageID) -> Void)?
    @State private var editing = false
    @State private var recalling = false
    @State private var reason = ""
    @State private var revisions = false
    @State private var localIssue = false
    @State private var editRecallSubmitting = false
    @State private var editRecallGeneration = 0
    @State private var pinSelection: NativeChannelMessagePinSelection?
    @Environment(\.scenePhase) private var phase
    private var current: Bool { coordinator.canDisplay(snapshot) && currentSnapshot() == snapshot && snapshot.status == 0 }
    private var canEdit: Bool {
        current && snapshot.kind == .text && snapshot.senderType == 1
            && snapshot.mentions != nil && snapshot.mentionEveryone != nil
            && snapshot.senderID?.rawValue == coordinator.client.identity.map({ String($0.accountID) })
            && coordinator.client.allows(.mutate(.edit))
    }
    private var canRecall: Bool {
        current && snapshot.senderType != nil && snapshot.senderType != 4
            && coordinator.client.allows(.mutate(.recall))
    }
    private var canConfirmEditRecall: Bool {
        coordinator.canStart && coordinator.client.allows(.receipt) && phase == .active && !editRecallSubmitting
    }
    func body(content: Content) -> some View {
        content.contextMenu {
            if current {
                if let quoteUsingOriginalSend { Button { quoteUsingOriginalSend(snapshot.id) } label: { Label { Text("message.quote", tableName: "NativeChannelMessage") } icon: { Image(systemName: "arrowshape.turn.up.left") } } }
                if canEdit {
                    Button { coordinator.prepareEdit(snapshot); editing = true } label: { Label { Text("message.edit", tableName: "NativeChannelMessage") } icon: { Image(systemName: "pencil") } }.disabled(!canConfirmEditRecall)
                }
                if snapshot.pinned != nil, coordinator.client.allows(.mutate(snapshot.pinned == true ? .unpin : .pin)) {
                    Button { preparePin() } label: {
                        Label { Text(snapshot.pinned == true ? "pins.remove" : "pins.add", tableName: "NativeChannelMessage") } icon: { Image(systemName: snapshot.pinned == true ? "pin.slash" : "pin") }
                    }.disabled(!coordinator.canStart || phase != .active || !coordinator.client.allows(.receipt))
                }
                if coordinator.client.allows(.revisions) { Button { revisions = true } label: { Label { Text("revisions.title", tableName: "NativeChannelMessage") } icon: { Image(systemName: "clock.arrow.circlepath") } } }
                if let reportUsingExistingOwner { Button { reportUsingExistingOwner(snapshot.id) } label: { Label { Text("message.report", tableName: "NativeChannelMessage") } icon: { Image(systemName: "exclamationmark.bubble") } } }
                // Destructive actions sit last, apart from the rest.
                if canRecall {
                    Divider()
                    Button(role: .destructive) { reason = ""; recalling = true } label: { Label { Text("message.recall", tableName: "NativeChannelMessage") } icon: { Image(systemName: "arrow.uturn.backward") } }.disabled(!canConfirmEditRecall)
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    Section {
                        TextEditor(text: $coordinator.draft).font(Theme.Font.body).frame(minHeight: 120).accessibilityIdentifier("ncm47.edit.draft")
                            .disabled(!canConfirmEditRecall || !canEdit)
                        if coordinator.draft.unicodeScalars.count > 2000 {
                            Text("d7.channelMessage.tooLong").font(.footnote).foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button { confirmEditRecall(.edit) } label: { Text("message.save", tableName: "NativeChannelMessage").frame(maxWidth: .infinity) }
                            .nativeChannelFlowAction()
                            .disabled(!canConfirmEditRecall || !canEdit || coordinator.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.draft.unicodeScalars.count > 2000)
                    }
                    NativeChannelMessageRecoveryView(coordinator: coordinator)
                }.nativeChannelScreen().navigationTitle(Text("message.edit", tableName: "NativeChannelMessage"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { closeEditRecall() } } }
            }.privacySensitive().onDisappear { editRecallGeneration += 1 }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $recalling) {
            NavigationStack {
                Form {
                    Section {
                        TextField("", text: $reason, prompt: Text("message.reason", tableName: "NativeChannelMessage"), axis: .vertical)
                            .lineLimit(1...4)
                            .disabled(!canConfirmEditRecall || !canRecall)
                        if !reason.isEmpty && !validRecallReason {
                            Text("d7.channelMessage.reasonLength").font(.footnote).foregroundStyle(.red)
                        }
                    } header: { Text("message.recallConfirm", tableName: "NativeChannelMessage") }
                    Section {
                        Button(role: .destructive) { confirmEditRecall(.recall) } label: { Text("message.recall", tableName: "NativeChannelMessage").frame(maxWidth: .infinity) }
                            .disabled(!canConfirmEditRecall || !canRecall || !validRecallReason)
                    }
                    NativeChannelMessageRecoveryView(coordinator: coordinator)
                }.nativeChannelScreen().navigationTitle(Text("message.recall", tableName: "NativeChannelMessage"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { closeEditRecall() } } }
            }.privacySensitive().onDisappear { editRecallGeneration += 1; reason = "" }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $revisions) {
            NavigationStack { NativeChannelMessageRevisionView(client: coordinator.client, messageID: snapshot.id) }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .confirmationDialog("d7.channelMessage.pinTitle", isPresented: Binding(
            get: { pinSelection != nil }, set: { if !$0 { pinSelection = nil } }), titleVisibility: .visible, presenting: pinSelection) { selection in
            Button { confirmPin(selection) } label: { Text(selection.command.operation == .pin ? "pins.add" : "pins.remove", tableName: "NativeChannelMessage") }
                .disabled(!current || !coordinator.canStart || phase != .active || !selection.isCurrent(coordinator.client))
            Button("action.cancel", role: .cancel) { pinSelection = nil }
        }
        .onChange(of: current) { _, valid in if !valid { pinSelection = nil } }
        .onChange(of: phase) { _, value in if value != .active { pinSelection = nil } }
        .onDisappear { pinSelection = nil }
        .onChange(of: canEdit) { _, valid in if !valid && editing { closeEditRecall() } }
        .onChange(of: canRecall) { _, valid in if !valid && recalling { closeEditRecall() } }
        .onChange(of: coordinator.client.allows(.receipt)) { _, valid in if !valid { pinSelection = nil; closeEditRecall() } }
        .onChange(of: phase) { _, value in if value != .active { closeEditRecall() } }
        .onDisappear { closeEditRecall() }
        .alert(Text("message.changed", tableName: "NativeChannelMessage"), isPresented: $localIssue) { Button("d7.channelChat.ok", role: .cancel) {} }
    }
    private func preparePin() {
        guard phase == .active, current, coordinator.canStart else { return }
        do { pinSelection = try .init(snapshot: snapshot, client: coordinator.client) }
        catch { localIssue = true }
    }
    private func confirmPin(_ selection: NativeChannelMessagePinSelection) {
        pinSelection = nil
        guard phase == .active, current, coordinator.canStart, selection.isCurrent(coordinator.client),
              currentSnapshot() == selection.snapshot else { localIssue = true; return }
        // Capture the confirmed UUID/action. Never recalculate a toggle after suspension.
        Task {
            guard phase == .active, current, coordinator.canStart, selection.isCurrent(coordinator.client),
                  currentSnapshot() == selection.snapshot else { return }
            await coordinator.submit(selection.command)
        }
    }
    private var validRecallReason: Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.utf16.count <= 200 && (snapshot.senderID?.rawValue == coordinator.client.identity.map({ String($0.accountID) }) || trimmed.utf16.count >= 4)
    }
    private func closeEditRecall() {
        editRecallGeneration += 1; editing = false; recalling = false; reason = ""
        // Only pre-dispatch UI is retired here. The original coordinator owns any saved request.
    }
    private func confirmEditRecall(_ operation: NativeChannelMessageOperation) {
        guard canConfirmEditRecall,
              operation == .edit ? canEdit : (operation == .recall && canRecall && validRecallReason) else { localIssue = true; return }
        do {
            // Freeze source version, body, retained mentions and UUID before creating the task.
            let command = try NativeChannelMessageCommand(operation: operation, requestID: UUID().uuidString,
                binding: coordinator.client.binding, messageID: snapshot.id,
                expectedVersion: operation == .edit || operation == .recall ? snapshot.version : nil,
                content: operation == .edit ? coordinator.draft : nil, reason: operation == .recall ? reason : nil,
                memberIDs: operation == .edit ? (snapshot.mentions ?? []).filter { $0.mention_type == "USER" }.compactMap { NativeChannelMessageID(rawValue: $0.member_id) } : [],
                roleIDs: operation == .edit ? (snapshot.mentions ?? []).filter { $0.mention_type == "ROLE" }.compactMap { NativeChannelMessageID(rawValue: $0.member_id) } : [],
                mentionEveryone: operation == .edit ? (snapshot.mentionEveryone == true) : false)
            let identity = coordinator.client.identity
            editRecallGeneration += 1; let run = editRecallGeneration; editRecallSubmitting = true
            Task {
                defer { editRecallSubmitting = false }
                guard run == editRecallGeneration, phase == .active, current, coordinator.canStart,
                      coordinator.client.identity == identity, coordinator.client.binding == command.binding,
                      coordinator.client.allows(.receipt), coordinator.client.allows(.mutate(operation)) else { return }
                await coordinator.submit(command)
                // UNKNOWN/rejection stays reachable in this form and in the normal channel recovery footer.
                if case .applied = coordinator.state { closeEditRecall() }
            }
        } catch { localIssue = true }
    }
}

/// Normal channel footer (also shown in the original edit/recall form).
/// The request proof and a later read-only source observation are deliberately separate.
@MainActor struct NativeChannelMessageEditRecallRecoveryView: View {
    @Bindable var coordinator: NativeChannelMessageCoordinator
    var body: some View {
        if coordinator.isCurrent, coordinator.client.allows(.receipt) {
            if let pending = coordinator.original, pending.operation == .edit || pending.operation == .recall {
                Label { Text("d7.channelMessage.changePending") } icon: { Image(systemName: "clock") }
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ncm47.editRecall.originalPending")
            }
            if coordinator.original == nil, let readback = coordinator.editRecallReadback.observation {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(readback.operation == .recall ? "d7.channelMessage.recallDone" : "d7.channelMessage.editDone"))
                    Group {
                        switch readback.state {
                        case .reading: Text("d7.channelMessage.reading")
                        case .visible(_, let atAppliedEditVersion):
                            Text(LocalizedStringKey(atAppliedEditVersion ? "d7.channelMessage.upToDate" : "d7.channelMessage.changedSince"))
                        case .unavailable: Text("d7.channelMessage.notVisible")
                        case .failed: Text("d7.channelMessage.readFailed")
                        case .accessClosed: Text("access.closed", tableName: "NativeChannelMessage")
                        }
                    }.foregroundStyle(.secondary)
                    Button("d7.channelMessage.refresh") { Task { await coordinator.editRecallReadback.refresh() } }
                        .disabled(coordinator.busy || coordinator.editRecallReadback.refreshing || !coordinator.editRecallReadback.canRefresh)
                }.accessibilityIdentifier("ncm47.editRecall.receiptAndCurrentMessage")
            }
        }
    }
}
