import SwiftUI

@MainActor struct NativeChannelMessagePinsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    private var copy: NativeChannelPinLocalization { .init(locale: locale) }
    @Bindable var coordinator: NativeChannelMessageCoordinator
    @State private var readTask: Task<Void, Never>?
    @State private var selectionTask: Task<Void, Never>?
    @State private var selectionGeneration = 0
    @State private var selecting = false
    @State private var pinSelection: NativeChannelMessagePinSelection?
    @State private var localIssue = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    var locateOriginal: ((NativeChannelMessageID) -> Void)?
    var body: some View {
        List {
            if coordinator.pins.loading { ProgressView().frame(maxWidth: .infinity) }
            else if !coordinator.pins.isCurrent {
                ContentUnavailableView { Label { Text("access.closed", tableName: "NativeChannelMessage") } icon: { Image(systemName: "lock") } }
            }
            else {
                if coordinator.pins.rows.isEmpty && !coordinator.pins.failed {
                    ContentUnavailableView { Label { Text("pins.empty", tableName: "NativeChannelMessage") } icon: { Image(systemName: "pin") } }
                }
                ForEach(coordinator.pins.rows) { pin in
                    Button { if coordinator.pins.isCurrent { locateOriginal?(pin.message_id) } } label: {
                        Label { Text(verbatim: pin.summary).lineLimit(typeSize.isAccessibilitySize ? nil : 3).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                    }.disabled(locateOriginal == nil)
                    .accessibilityIdentifier("ncm47.pin.\(pin.id.rawValue)")
                    .swipeActions {
                        if coordinator.client.allows(.mutate(.unpin)) {
                            Button(role: .destructive) { prepareRemoval(pin) } label: { Text("pins.remove", tableName: "NativeChannelMessage") }.disabled(!coordinator.canStart || selecting || pinSelection != nil || !coordinator.client.allows(.context) || !coordinator.client.allows(.receipt))
                        }
                    }
                }.onMove { offsets, destination in
                    reorder(offsets, to: destination)
                }.moveDisabled(!coordinator.canStart || !coordinator.client.allows(.mutate(.sort)) || !coordinator.client.allows(.receipt))
            }
            if selecting { ProgressView(copy.text("p23.selecting")) }
            if coordinator.pins.failed {
                Section {
                    Label { Text("load.failed", tableName: "NativeChannelMessage") } icon: { Image(systemName: "exclamationmark.triangle") }
                    Button(copy.text("p23.reload")) { reload() }
                        .disabled(!coordinator.pins.isCurrent || phase != .active)
                }
            }
            NativeChannelMessageRecoveryView(coordinator: coordinator)
        }
        .nativeChannelScreen().listStyle(.insetGrouped)
        .navigationTitle(Text("pins.title", tableName: "NativeChannelMessage"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("action.done") { dismiss() } }
            if coordinator.client.allows(.mutate(.sort)) {
                ToolbarItem(placement: .primaryAction) {
                    EditButton().disabled(!coordinator.canStart || !coordinator.pins.isCurrent || coordinator.pins.loading)
                }
            }
        }
        .task(id: phase) {
            guard phase == .active else { retireRead(); return }
            await coordinator.pins.activate()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                guard coordinator.pins.isCurrent else { retireRead(); return }
                // Original pin/unpin/order changes do not all enter the message mutation log.
                // Refresh only this presented reader; never replay a pin mutation here.
                if !coordinator.busy && !coordinator.pins.loading { await coordinator.pins.reload() }
            }
        }
        .refreshable { await coordinator.pins.reload() }
        .confirmationDialog(copy.text("p23.confirm.title"), isPresented: Binding(
            get: { pinSelection != nil }, set: { if !$0 { pinSelection = nil } }), titleVisibility: .visible, presenting: pinSelection) { selection in
            Button(copy.text("p23.confirm.action"), role: .destructive) { confirmRemoval(selection) }
                .disabled(!coordinator.canStart || !selectionIsCurrent(selection))
            Button(copy.text("p23.cancel"), role: .cancel) { pinSelection = nil }
        }
        .alert(copy.text("p23.changed"), isPresented: $localIssue) { Button(copy.text("p23.ok"), role: .cancel) {} }
        .onChange(of: coordinator.pins.isCurrent) { _, current in if !current { retireRead() } }
        .onChange(of: coordinator.client.allows(.receipt)) { _, allowed in
            if !allowed {
                selectionGeneration += 1; selectionTask?.cancel(); selectionTask = nil
                pinSelection = nil; selecting = false
            }
        }
        .onDisappear { retireRead() }
        .privacySensitive()
    }
    private func reload() {
        guard phase == .active, coordinator.pins.isCurrent else { retireRead(); return }
        readTask?.cancel()
        readTask = Task { await coordinator.pins.reload() }
    }
    private func retireRead() {
        selectionGeneration += 1; selectionTask?.cancel(); selectionTask = nil
        pinSelection = nil; selecting = false
        readTask?.cancel(); readTask = nil; coordinator.pins.retire()
    }
    private func prepareRemoval(_ pin: NativeChannelMessagePin) {
        guard phase == .active, coordinator.pins.isCurrent, coordinator.canStart, !selecting,
              coordinator.pins.rows.contains(pin), coordinator.client.allows(.context),
              coordinator.client.allows(.receipt) else { return }
        selectionGeneration += 1; let run = selectionGeneration
        let identity = coordinator.client.identity, binding = coordinator.client.binding
        selecting = true; pinSelection = nil
        selectionTask = Task {
            defer { if run == selectionGeneration { selecting = false } }
            do {
                // The list has no message version. Obtain it from the original read-only context,
                // never fabricate a version from sort_no, a pin id, or a successful writer result.
                let page = try await coordinator.client.context(messageID: pin.message_id)
                guard !Task.isCancelled, run == selectionGeneration, phase == .active,
                      coordinator.pins.isCurrent, coordinator.canStart,
                      coordinator.client.identity == identity, coordinator.client.binding == binding,
                      coordinator.pins.rows.contains(pin) else { return }
                try page.verify(binding: binding, anchor: pin.message_id)
                pinSelection = try .init(snapshot: page.anchor, client: coordinator.client, sourcePin: pin)
            } catch { if run == selectionGeneration && !Task.isCancelled { localIssue = true } }
        }
    }
    private func selectionIsCurrent(_ selection: NativeChannelMessagePinSelection) -> Bool {
        phase == .active && coordinator.pins.isCurrent && selection.isCurrent(coordinator.client)
            && coordinator.client.allows(.context)
            && selection.sourcePin.map { coordinator.pins.rows.contains($0) } == true
    }
    private func confirmRemoval(_ selection: NativeChannelMessagePinSelection) {
        pinSelection = nil
        guard coordinator.canStart, selectionIsCurrent(selection) else { localIssue = true; return }
        selectionGeneration += 1; let run = selectionGeneration; selecting = true
        selectionTask = Task {
            defer { if run == selectionGeneration { selecting = false } }
            do {
                let page = try await coordinator.client.context(messageID: selection.snapshot.id)
                guard !Task.isCancelled, run == selectionGeneration, coordinator.canStart,
                      selectionIsCurrent(selection) else { return }
                try page.verify(binding: selection.command.binding, anchor: selection.snapshot.id)
                guard page.anchor == selection.snapshot else { localIssue = true; return }
                // After this boundary the original coordinator owns persistence and dispatch.
                // Cancel/dismiss may cancel the preparation read, never a stored request.
                Task {
                    guard phase == .active, coordinator.canStart, selectionIsCurrent(selection) else { return }
                    await coordinator.submit(selection.command)
                }
            } catch { if run == selectionGeneration && !Task.isCancelled { localIssue = true } }
        }
    }
    private func reorder(_ offsets: IndexSet, to destination: Int) {
        // Capture the user's visible ordered IDs synchronously, not offsets after a refresh.
        guard phase == .active, coordinator.pins.isCurrent, coordinator.canStart,
              let ids = try? coordinator.pins.orderedIDs(offsets, to: destination),
              let command = try? NativeChannelMessageCommand(operation: .sort, requestID: UUID().uuidString,
                  binding: coordinator.client.binding, orderedPinIDs: ids) else { return }
        submit(command)
    }
    private func submit(_ command: NativeChannelMessageCommand) {
        // Once dispatched, the existing journal/coordinator owns the mutation and recovery.
        // Dismissal cancels reads only; it must not discard or replace an uncertain write.
        Task {
            guard phase == .active, coordinator.pins.isCurrent else { return }
            await coordinator.submit(command)
        }
    }
}

/// Display only: never derive operations from localized prose or change wire values.
@MainActor struct NativeChannelPinLocalization {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
            table: "NativeChannelMessage", locale: locale))
    }
    func format(_ key: String, _ values: String...) -> String {
        String(format: text(key), locale: locale, arguments: values.map { $0 as CVarArg })
    }
    func operation(_ value: NativeChannelMessageOperation) -> String {
        switch value {
        case .pin: return text("p23.operation.pin")
        case .unpin: return text("p23.operation.unpin")
        case .sort: return text("p23.operation.sort")
        default: return value.rawValue // Other original operations remain untouched.
        }
    }
}
