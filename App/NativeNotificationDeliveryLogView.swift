import SwiftUI

@MainActor struct NativeNotificationDeliveryLogView: View {
    @Environment(\.scenePhase) private var phase
    let makeFlow: () -> NativeNotificationDeliveryLogCoordinator?
    @State private var model: NativeNotificationDeliveryLogCoordinator?
    @State private var event = ""
    @State private var attempted = false
    @State private var visible = false
    @State private var readGeneration: UInt64 = 0
    @State private var readTask: Task<Void, Never>?
    var body: some View {
        List {
            if let model, model.isCurrent {
                Section {
                    TextField("d7.deliveryLog.filter", text: $event)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { search() }
                        .disabled(model.isBusy || readTask != nil)
                    Button("d7.deliveryLog.search") { search() }
                        .disabled(!model.canRead || readTask != nil)
                }
                if let page = model.page {
                    if page.list.isEmpty {
                        ContentUnavailableView("d7.deliveryLog.empty", systemImage: "bell.slash")
                    } else {
                        Section {
                            ForEach(page.list) { row in
                                LabeledContent {
                                    Text(resultKey(row))
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: row.event ?? "—").font(.headline)
                                        HStack(spacing: 4) {
                                            Text(row.channel == "wx" ? LocalizedStringKey("d7.deliveryLog.channel.wx") : LocalizedStringKey("d7.deliveryLog.channel.push"))
                                            Text(verbatim: "·")
                                            Text(verbatim: String(row.createTime.prefix(16)))
                                        }
                                        .font(.footnote).foregroundStyle(.secondary)
                                        if let reason = row.reason { Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary) }
                                    }
                                }
                                .privacySensitive()
                            }
                            if model.canReadNext {
                                Button("d7.deliveryLog.next") { performRead { await $0.readNext() } }.disabled(readTask != nil)
                            }
                        }
                    }
                }
                if model.state == .loading { ProgressView().frame(maxWidth: .infinity) }
                if model.state == .unavailable {
                    ContentUnavailableView {
                        Label("d7.deliveryLog.failed", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("d7.deliveryLog.retry") { performRead { await $0.rereadPage() } }
                            .disabled(!model.canRead || readTask != nil)
                    }
                }
            } else if model?.state == .idle {
                ProgressView().frame(maxWidth: .infinity)
            } else if attempted {
                ContentUnavailableView("d7.deliveryLog.unavailable", systemImage: "list.bullet.rectangle")
            } else { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("d7.deliveryLog.title")).privacySensitive()
        // Pull to refresh rereads the current page (the old "reload current page" button).
        .refreshable { if model?.page != nil { performRead { await $0.rereadPage() } } }
        .onAppear { visible = true; reopen() }
        .onChange(of: phase) { _, value in
            if value == .active { reopen() } else { clear() }
        }
        .onChange(of: model?.isCurrent) { _, current in
            // A newly acquired idle reader has not started yet. Its queued activation
            // is owned below; a closed or revoked active reader must be retired now.
            if current == false, let model, !model.isCurrent, model.state != .idle { clear() }
        }
        .onDisappear { visible = false; clear() }
    }
    private func clear() {
        readGeneration &+= 1
        readTask?.cancel(); readTask = nil
        model?.deactivate(); model = nil; event = ""
    }
    private func reopen() {
        clear(); attempted = true
        guard visible, phase == .active else { return }
        guard let candidate = makeFlow() else { return }
        model = candidate
        startRead(candidate) { await $0.activate() }
    }
    private func performRead(_ operation: @escaping @MainActor (NativeNotificationDeliveryLogCoordinator) async -> Void) {
        guard visible, phase == .active, readTask == nil, let candidate = model, candidate.canRead else { return }
        startRead(candidate, operation: operation)
    }
    private func startRead(_ candidate: NativeNotificationDeliveryLogCoordinator,
                           operation: @escaping @MainActor (NativeNotificationDeliveryLogCoordinator) async -> Void) {
        readGeneration &+= 1
        let ticket = readGeneration
        readTask = Task { @MainActor in
            guard !Task.isCancelled, owns(candidate, ticket: ticket) else { candidate.deactivate(); return }
            await operation(candidate)
            guard !Task.isCancelled, owns(candidate, ticket: ticket) else { candidate.deactivate(); return }
            readTask = nil
        }
    }
    private func owns(_ candidate: NativeNotificationDeliveryLogCoordinator, ticket: UInt64) -> Bool {
        visible && phase == .active && readGeneration == ticket && model === candidate
    }
    private func search() {
        let chosen = event.trimmingCharacters(in: .whitespacesAndNewlines)
        performRead { await $0.refresh(event: chosen.isEmpty ? nil : chosen) }
    }
    private func resultKey(_ row: NativeNotificationDeliveryLogPage.Row) -> LocalizedStringKey {
        if row.sourceConflict { return "d7.deliveryLog.result.unknown" }
        if row.channel == "wx" { return row.ok == 1 ? "d7.deliveryLog.result.sent" : row.ok == 0 ? "d7.deliveryLog.result.notSent" : "d7.deliveryLog.result.unknown" }
        switch row.providerState {
        case "PROVIDER_ACCEPTED": return "d7.deliveryLog.result.sent"
        case "PROVIDER_REJECTED": return "d7.deliveryLog.result.failed"
        case "SUPPRESSED": return "d7.deliveryLog.result.skipped"
        case "NOT_ATTEMPTED": return "d7.deliveryLog.result.notSent"
        default: return "d7.deliveryLog.result.unknown"
        }
    }
}
