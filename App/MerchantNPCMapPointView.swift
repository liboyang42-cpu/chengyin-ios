import SwiftUI

/// Source-like row in the NPC settings page. A failed read is never shown as a saved point.
@MainActor struct MerchantNPCMapPointEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @StateObject private var point: MerchantOperationsViewModel
    init(document: MerchantOperationsViewModel) {
        self.document = document
        _point = StateObject(wrappedValue: .init(reader: document.coordinator.reader, destination: .npcMapPoint))
    }
    var body: some View {
        Section {
            NavigationLink {
                MerchantOperationsDocumentView(reader: document.coordinator.reader, destination: .npcMapPoint)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("merchantMapPoint.title", systemImage: "mappin.and.ellipse")
                    if point.coordinator.isCurrent, case .npcMapPoint(let saved) = point.coordinator.baseline {
                        Text(LocalizedStringKey(saved.statusKey)).font(.subheadline).foregroundStyle(.secondary)
                        if saved.coordinate != nil, !saved.address.isEmpty { Text(verbatim: saved.address).font(.footnote) }
                    } else if let issue = point.coordinator.issue {
                        MerchantOperationsIssueView(issue: issue)
                    } else { Text("merchant.loading").font(.footnote) }
                }
            }.disabled(!document.coordinator.isCurrent || document.coordinator.isBusy || document.coordinator.isLocked)
                .accessibilityIdentifier("merchantMapPoint.open")
        }
        .task(id: document.coordinator.reader.scope) { await point.load() }
        .onChange(of: document.coordinator.reader.scope) { _, _ in point.invalidate() }
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
