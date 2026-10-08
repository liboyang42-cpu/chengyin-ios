import SwiftUI

@MainActor final class MerchantNPCMapPointReadOnlyModel: ObservableObject {
    struct RefreshIntent: Equatable {
        fileprivate let appearanceID: UUID
        fileprivate let scope: UUID
    }
    let coordinator: MerchantNPCMapPointReadOnlyCoordinator
    @Published private(set) var revision = 0
    private var isVisible = false
    private var activeIntent: RefreshIntent?
    init(reader: any MerchantOperationsReading) { coordinator = .init(reader: reader) }
    var refreshIntent: RefreshIntent? {
        guard isVisible, let activeIntent, activeIntent.scope == coordinator.reader.scope else { return nil }
        return activeIntent
    }
    // Activation is a synchronous appearance event, never something a queued task can do.
    func appear(isActive: Bool = true) {
        isVisible = true
        suspend()
        if isActive { activeIntent = .init(appearanceID: UUID(), scope: coordinator.reader.scope) }
    }
    func disappear() { isVisible = false; suspend() }
    func suspend() { activeIntent = nil; coordinator.invalidate(); revision += 1 }
    func resume() -> RefreshIntent? {
        guard isVisible else { return nil }
        appear(); return refreshIntent
    }
    func scopeChanged() -> RefreshIntent? {
        let wasActive = activeIntent != nil
        suspend()
        guard isVisible, wasActive else { return nil }
        activeIntent = .init(appearanceID: UUID(), scope: coordinator.reader.scope)
        return refreshIntent
    }
    func load(_ intent: RefreshIntent?) async {
        // Check before entering the coordinator: a closed, replaced or cancelled task
        // must not even dispatch access/me under a newer visible appearance.
        guard !Task.isCancelled, let intent, intent == refreshIntent else { return }
        revision += 1
        await coordinator.load()
        guard intent == refreshIntent else { return }
        revision += 1
    }
}

/// Source-like row in the NPC settings page. A failed read is never shown as a saved point.
@MainActor struct MerchantNPCMapPointEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @StateObject private var point: MerchantNPCMapPointReadOnlyModel
    @Environment(\.scenePhase) private var scenePhase
    init(document: MerchantOperationsViewModel) {
        self.document = document
        _point = StateObject(wrappedValue: .init(reader: document.coordinator.reader))
    }
    var body: some View {
        Section {
            NavigationLink {
                MerchantNPCMapPointReadOnlyView(reader: document.coordinator.reader)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("merchantMapPoint.title", systemImage: "mappin.and.ellipse")
                    if let saved = point.coordinator.point {
                        Text(LocalizedStringKey(saved.statusKey)).font(.subheadline).foregroundStyle(.secondary)
                        if saved.coordinate != nil, !saved.address.isEmpty { Text(verbatim: saved.address).font(.footnote) }
                    } else if let issue = point.coordinator.issue, point.coordinator.loadedScope == document.coordinator.reader.scope {
                        MerchantOperationsIssueView(issue: issue)
                    } else { Text("merchant.loading").font(.footnote) }
                }
            }.disabled(!document.coordinator.isCurrent || document.coordinator.isBusy)
                .accessibilityIdentifier("merchantMapPoint.open")
        }
        .onAppear { point.appear(isActive: scenePhase == .active) }
        .task(id: point.refreshIntent) { [intent = point.refreshIntent] in await point.load(intent) }
        .onChange(of: document.coordinator.reader.scope) { _, _ in _ = point.scopeChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { point.suspend() }
            else { _ = point.resume() }
        }
        .onDisappear { point.disappear() }
    }
}

/// Every authorized role can inspect the saved point. Only a fresh dual-permission
/// snapshot exposes the existing editor, whose service independently rechecks writes.
@MainActor struct MerchantNPCMapPointReadOnlyView: View {
    let reader: any MerchantOperationsReading
    @StateObject private var model: MerchantNPCMapPointReadOnlyModel
    @State private var showEditor = false
    @Environment(\.scenePhase) private var scenePhase
    init(reader: any MerchantOperationsReading) {
        self.reader = reader
        _model = StateObject(wrappedValue: .init(reader: reader))
    }
    private var coordinator: MerchantNPCMapPointReadOnlyCoordinator { model.coordinator }
    var body: some View {
        Form {
            Section { MerchantOperationsBoundary(isExample: reader.isOfflineExample) }
            if let saved = coordinator.point {
                Section("merchantMapPoint.title") {
                    Text("merchantMapPoint.lastRead").font(.caption).foregroundStyle(.secondary)
                    Text(LocalizedStringKey(saved.statusKey)).accessibilityIdentifier("merchantMapPoint.status")
                    if saved.coordinate != nil { MerchantNPCMapPointSummary(value: saved) }
                    Text("merchantMapPoint.displayOnly").font(.footnote).foregroundStyle(.secondary)
                }
                if coordinator.hasPendingWrite {
                    Section { Text("merchant.operations.unknownOutcome") }
                } else if coordinator.canOpenEditor {
                    Section {
                        Button("merchantMapPoint.edit") {
                            guard coordinator.canOpenEditor else { return }
                            showEditor = true
                        }.accessibilityIdentifier("merchantMapPoint.edit")
                    }
                } else {
                    Section { Text("merchantMapPoint.readOnly").accessibilityIdentifier("merchantMapPoint.readOnly") }
                }
            } else if let issue = coordinator.issue, coordinator.loadedScope == reader.scope {
                Section { MerchantOperationsIssueView(issue: issue) }
            } else { ProgressView("merchant.loading") }
        }
        .appNavigationTitle(key: MerchantOperationsDestination.npcMapPoint.titleKey)
        .accessibilityIdentifier("merchantMapPoint.details")
        // Keep the pushed editor independent of the read snapshot cleared on disappear.
        .navigationDestination(isPresented: $showEditor) {
            MerchantOperationsDocumentView(reader: reader, destination: .npcMapPoint)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("merchant.operations.reloadSource", systemImage: "arrow.clockwise") {
                    let intent = model.refreshIntent
                    Task { await model.load(intent) }
                }.disabled(coordinator.isBusy).accessibilityIdentifier("merchantMapPoint.reload")
            }
        }
        .onAppear { model.appear(isActive: scenePhase == .active) }
        .task(id: model.refreshIntent) { [intent = model.refreshIntent] in await model.load(intent) }
        .onChange(of: reader.scope) { _, _ in _ = model.scopeChanged(); showEditor = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.suspend() }
            else { _ = model.resume() }
        }
        .onDisappear { model.disappear() }
    }
}

/// Edits stay in this sheet until explicitly applied. The shared coordinator owns immutable
/// review, permission rechecks, durable unknown-write lock and server readback.
@MainActor final class MerchantNPCMapPointManualModel: ObservableObject {
    @Published private(set) var latitude: String
    @Published private(set) var longitude: String
    @Published private(set) var address: String
    @Published private(set) var confirmedDatum: WalkingCoordinateDatum?
    private weak var document: MerchantOperationsViewModel?
    private let original: MerchantNPCMapPoint
    private let scope: UUID
    private let draftIdentity: UUID
    private var consumed = false
    init?(document: MerchantOperationsViewModel) {
        let owner = document.coordinator
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .npcMapPoint(let value) = owner.draft else { return nil }
        self.document = document; original = value; scope = owner.reader.scope; draftIdentity = owner.draftIdentity
        latitude = value.latitude; longitude = value.longitude; address = value.address
        confirmedDatum = nil
    }
    var isCurrent: Bool {
        guard !consumed, let owner = document?.coordinator else { return false }
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil &&
            owner.reader.scope == scope && owner.draftIdentity == draftIdentity && owner.draft == .npcMapPoint(original)
    }
    var candidate: MerchantNPCMapPoint? {
        guard isCurrent else { return nil }
        return try? original.replacing(latitude: latitude, longitude: longitude, address: address, confirmedDatum: confirmedDatum)
    }
    var canApply: Bool { candidate.map { $0 != original } ?? false }
    func setLatitude(_ value: String) { guard isCurrent else { return }; latitude = value; confirmedDatum = nil }
    func setLongitude(_ value: String) { guard isCurrent else { return }; longitude = value; confirmedDatum = nil }
    func setAddress(_ value: String) { guard isCurrent else { return }; address = value; confirmedDatum = nil }
    func confirmDatum(_ value: WalkingCoordinateDatum?) { guard isCurrent else { return }; confirmedDatum = value }
    @discardableResult func apply() -> Bool {
        guard canApply, let candidate, let document else { return false }
        consumed = true
        document.edit(.npcMapPoint(candidate))
        return document.coordinator.draft == .npcMapPoint(candidate)
    }
    func cancel() { consumed = true; latitude = ""; longitude = ""; address = ""; confirmedDatum = nil }
}

@MainActor struct MerchantNPCMapPointFields: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @State private var manual: Presentation?
    @Environment(\.scenePhase) private var scenePhase
    private struct Presentation: Identifiable { let id = UUID(); let model: MerchantNPCMapPointManualModel }
    var body: some View {
        Section("merchantMapPoint.title") {
            if case .npcMapPoint(let saved) = document.coordinator.baseline {
                Text("merchantMapPoint.lastRead").font(.caption).foregroundStyle(.secondary)
                Text(LocalizedStringKey(saved.statusKey)).accessibilityIdentifier("merchantMapPoint.status")
                if saved.coordinate != nil { MerchantNPCMapPointSummary(value: saved) }
            }
            Text("merchantMapPoint.displayOnly").font(.footnote).foregroundStyle(.secondary)
            Text("merchantMapPoint.mapUnavailable").font(.footnote).foregroundStyle(.secondary)
            if document.coordinator.isDirty, case .npcMapPoint(let proposed) = document.coordinator.draft {
                Text("merchantMapPoint.unsaved").font(.headline)
                MerchantNPCMapPointSummary(value: proposed)
            }
            Button("merchantMapPoint.enter") {
                guard scenePhase == .active, let model = MerchantNPCMapPointManualModel(document: document) else { return }
                manual = .init(model: model)
            }.frame(minHeight: 44)
                .disabled(!document.coordinator.isCurrent || document.coordinator.isBusy || document.coordinator.isLocked || document.coordinator.confirmation != nil)
                .accessibilityIdentifier("merchantMapPoint.enter")
        }
        .sheet(item: $manual, onDismiss: cancelManual) { presentation in
            MerchantNPCMapPointManualView(model: presentation.model)
        }
        .onChange(of: document.coordinator.reader.scope) { _, _ in cancelManual() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in cancelManual() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelManual(); document.cancel() }
        }
        .onDisappear { cancelManual() }
    }
    private func cancelManual() { manual?.model.cancel(); manual = nil }
}

@MainActor private struct MerchantNPCMapPointManualView: View {
    @ObservedObject var model: MerchantNPCMapPointManualModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchantMapPoint.manualHint")
                    TextField("merchantMapPoint.latitude", text: Binding(get: { model.latitude }, set: model.setLatitude))
                        .keyboardType(.numbersAndPunctuation).focused($typing).accessibilityIdentifier("merchantMapPoint.latitude")
                    TextField("merchantMapPoint.longitude", text: Binding(get: { model.longitude }, set: model.setLongitude))
                        .keyboardType(.numbersAndPunctuation).focused($typing).accessibilityIdentifier("merchantMapPoint.longitude")
                    TextField("merchantMapPoint.address", text: Binding(get: { model.address }, set: model.setAddress), axis: .vertical)
                        .focused($typing).accessibilityIdentifier("merchantMapPoint.address")
                    Toggle("merchantMapPoint.confirmDatum", isOn: Binding(get: { model.confirmedDatum == .gcj02 }, set: { model.confirmDatum($0 ? .gcj02 : nil) }))
                        .accessibilityIdentifier("merchantMapPoint.confirmDatum")
                    if model.confirmedDatum != nil, model.candidate == nil {
                        Text("merchantMapPoint.invalidInput").foregroundStyle(.secondary).accessibilityIdentifier("merchantMapPoint.invalidInput")
                    }
                }
                if let candidate = model.candidate {
                    Section("merchantMapPoint.exactDraft") { MerchantNPCMapPointSummary(value: candidate) }
                }
                Section {
                    Button("merchantMapPoint.apply") {
                        typing = false
                        if model.apply() { dismiss() }
                    }.disabled(!model.canApply).frame(minHeight: 44).accessibilityIdentifier("merchantMapPoint.apply")
                    Text("merchantMapPoint.reviewNext").font(.footnote).foregroundStyle(.secondary)
                }
            }.disabled(!model.isCurrent)
                .navigationTitle("merchantMapPoint.title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.cancel") { model.cancel(); dismiss() }.accessibilityIdentifier("merchantMapPoint.cancel")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("action.done") { typing = false } }
                }
        }.privacySensitive().onDisappear { model.cancel() }
    }
}

private struct MerchantNPCMapPointSummary: View {
    let value: MerchantNPCMapPoint
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("merchantMapPoint.latitude", value: value.latitude)
            LabeledContent("merchantMapPoint.longitude", value: value.longitude)
            LabeledContent("merchantMapPoint.datum", value: "GCJ-02")
            if !value.address.isEmpty { LabeledContent("merchantMapPoint.address", value: value.address) }
        }.textSelection(.enabled).privacySensitive().accessibilityIdentifier("merchantMapPoint.summary")
    }
}
